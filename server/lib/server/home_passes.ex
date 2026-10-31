defmodule Server.HomePasses do
  @moduledoc """
  One-off home invites (FR-3). When a player accepts an invite from someone who isn't their friend,
  they get a PASS: good for one visit to that home, used up the moment they walk in, and gone after a
  few minutes if unused. Transient by design (an Agent, not the database): a pass is for "come with me
  now", and a server restart simply means asking again.
  """
  use Agent

  @ttl_ms 10 * 60 * 1000
  # An invite waits this long for an answer before it lapses.
  @offer_ttl_ms 2 * 60 * 1000

  def start_link(_opts), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  @doc """
  `owner` invites `guest`. The offer must exist for an acceptance to count, so a client can't
  "accept" an invite nobody sent. Lapses after a couple of minutes.
  """
  @spec offer(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def offer(owner, guest) do
    expires = System.monotonic_time(:millisecond) + @offer_ttl_ms
    Agent.update(__MODULE__, &Map.put(&1, {:offer, owner, guest}, expires))
  end

  @doc "Take (use up) `owner`'s offer to `guest`. True if there was a live one."
  @spec take_offer(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def take_offer(owner, guest) do
    now = System.monotonic_time(:millisecond)

    Agent.get_and_update(__MODULE__, fn m ->
      {live?(Map.get(m, {:offer, owner, guest}), now), Map.delete(m, {:offer, owner, guest})}
    end)
  end

  @doc "Give `guest` a one-visit pass to `owner`'s home."
  @spec grant(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def grant(owner, guest) do
    expires = System.monotonic_time(:millisecond) + @ttl_ms
    Agent.update(__MODULE__, &Map.put(&1, {owner, guest}, expires))
  end

  @doc "Whether `guest` holds an unexpired pass to `owner`'s home."
  @spec valid?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def valid?(owner, guest) do
    now = System.monotonic_time(:millisecond)
    Agent.get(__MODULE__, fn passes -> live?(Map.get(passes, {owner, guest}), now) end)
  end

  @doc "Use up `guest`'s pass to `owner`'s home (called when they walk in)."
  @spec consume(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def consume(owner, guest), do: Agent.update(__MODULE__, &Map.delete(&1, {owner, guest}))

  @doc "Drop every pass into `owner`'s home (they closed it) or held by/for a blocked player."
  @spec revoke(Ecto.UUID.t(), Ecto.UUID.t() | :all) :: :ok
  def revoke(owner, :all) do
    Agent.update(__MODULE__, &Map.reject(&1, fn {key, _} -> owner_of(key) == owner end))
  end

  def revoke(owner, guest) do
    Agent.update(__MODULE__, &Map.drop(&1, [{owner, guest}, {guest, owner}, {:offer, owner, guest}, {:offer, guest, owner}]))
  end

  # Monotonic time can be negative, so "no entry" must never be mistaken for a time.
  defp live?(nil, _now), do: false
  defp live?(expires, now), do: expires > now

  defp owner_of({:offer, owner, _guest}), do: owner
  defp owner_of({owner, _guest}), do: owner
end
