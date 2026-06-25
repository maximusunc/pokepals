defmodule Server.TradeSession do
  @moduledoc """
  The COORDINATION half of a trade (§6.4) — a short-lived process holding both sides' offers and
  confirms while they haggle. It is NOT authoritative: it never moves an asset. When both parties
  have confirmed the *current* offers, it hands them to `Server.Economy.execute_trade/1`, which
  re-verifies everything under lock — so even a buggy or malicious session can't dupe.

  Lifecycle: `start_link/1` with the two parties → `offer/3` (any new offer clears prior confirms, so
  you always confirm what you currently see) → `confirm/2`. The second confirm triggers execution and
  the process stops, returning the result. A TTL stops an abandoned session.

  These would be started under a `DynamicSupervisor` and addressed via the world/channel layer once
  the game has a trade UI; for now they're started directly (e.g. in tests).

  ── DEFERRED SEAM: rate-limit `confirm/2` (and offer spam) with a limiter (Hammer, ETS-backed) when
  there's a real surface to abuse. The anti-dupe guarantee does NOT depend on it. ──
  """
  use GenServer, restart: :temporary

  @default_ttl_ms 60_000

  # --- client API ---

  @doc "Start a session between two parties. Opts: `:a`, `:b` (required), `:ttl` ms (optional)."
  def start_link(opts) do
    a = Keyword.fetch!(opts, :a)
    b = Keyword.fetch!(opts, :b)
    ttl = Keyword.get(opts, :ttl, @default_ttl_ms)
    GenServer.start_link(__MODULE__, {a, b, ttl})
  end

  @doc "Set a party's current offer: `%{items: [instance_id], currency: %{type => amount}}`."
  def offer(session, user_id, offer), do: GenServer.call(session, {:offer, user_id, offer})

  @doc """
  Confirm the current offers for a party. Returns `:waiting` until both have confirmed; the second
  confirm executes the trade and returns `{:ok, correlation_id}` or `{:error, reason}`, then stops.
  """
  def confirm(session, user_id), do: GenServer.call(session, {:confirm, user_id})

  @doc "Abandon the session."
  def cancel(session), do: GenServer.stop(session, :normal)

  # --- server callbacks ---

  @impl true
  def init({a, b, ttl}) do
    Process.send_after(self(), :expire, ttl)
    {:ok, %{a: a, b: b, offers: %{a => empty_offer(), b => empty_offer()}, confirms: MapSet.new()}}
  end

  @impl true
  def handle_call({:offer, user_id, offer}, _from, state) do
    if party?(state, user_id) do
      offers = Map.put(state.offers, user_id, normalize(offer))
      # Any change to the table invalidates standing confirms — you re-confirm what you now see.
      {:reply, :ok, %{state | offers: offers, confirms: MapSet.new()}}
    else
      {:reply, {:error, :not_a_party}, state}
    end
  end

  def handle_call({:confirm, user_id}, _from, state) do
    cond do
      not party?(state, user_id) ->
        {:reply, {:error, :not_a_party}, state}

      true ->
        # DEFERRED SEAM: rate-limit this confirm (Hammer) before doing work.
        confirms = MapSet.put(state.confirms, user_id)

        if MapSet.member?(confirms, state.a) and MapSet.member?(confirms, state.b) do
          result = Server.Economy.execute_trade(build_trade(state))
          {:stop, :normal, result, state}
        else
          {:reply, :waiting, %{state | confirms: confirms}}
        end
    end
  end

  @impl true
  def handle_info(:expire, state), do: {:stop, :normal, state}
  def handle_info(_msg, state), do: {:noreply, state}

  # --- internals ---

  defp party?(%{a: a, b: b}, user_id), do: user_id == a or user_id == b

  defp empty_offer, do: %{items: [], currency: %{}}

  defp normalize(offer) do
    %{
      items: Map.get(offer, :items, []),
      currency: Map.get(offer, :currency, %{})
    }
  end

  defp build_trade(%{a: a, b: b, offers: offers}) do
    %{
      a: a,
      b: b,
      a_items: offers[a].items,
      a_currency: offers[a].currency,
      b_items: offers[b].items,
      b_currency: offers[b].currency,
      context: %{trade_session: true}
    }
  end
end
