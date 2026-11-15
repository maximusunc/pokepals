defmodule Server.House do
  @moduledoc """
  YOUR HOUSE (home building, docs/usable-items-design.md "Home building"). Bring the **carpenter** in the
  bazaar (a prop with `"builds": "house"`) **100 wood** and **300 coins**, and she agrees to build you a
  house. From then on she's at your home, working on it, in the north of your glade; after `build_ms` (10
  minutes) it's done and you can go in. Your finds move in with you (`Server.HomeWorld`).

  One house per player. The commission is ONE transaction: the wood consumed, the coins sunk, and the house
  started, all together (ledgered through `Server.Economy`), so nothing is lost or made from nothing.

  Stored on the home's record (`homes.house`, a map): `%{"started_at" => unix_ms}`. Whether it's built is
  worked out from that and the CURRENT `build_ms`, so changing the build time applies at once, even to a
  house already going up.

  Tunables (`config :server, Server.House`; see config.exs and runtime.exs): `wood`, `coins`, `build_ms`.
  """
  alias Server.{Economy, Harvest, Homes, Repo}

  @defaults [wood: 100, coins: 300, build_ms: 600_000]
  @reach 90.0

  defp cfg(key),
    do: Keyword.get(Application.get_env(:server, __MODULE__, []), key, @defaults[key])

  def wood_cost, do: cfg(:wood)
  def coin_cost, do: cfg(:coins)
  def build_ms, do: cfg(:build_ms)

  @doc """
  A house's state from its stored record at `now` (unix ms): `"none"`, `"building"` or `"built"`. Pure.
  """
  @spec state(map() | nil, integer()) :: String.t()
  def state(%{"started_at" => started}, now) when is_integer(started) do
    if now - started >= build_ms(), do: "built", else: "building"
  end

  def state(_house, _now), do: "none"

  @doc """
  The house as the client is told it: `%{state, started_at, build_ms, left_ms, wood, coins}`. `left_ms` is
  0 once built (and when there's no house).
  """
  @spec status(Ecto.UUID.t()) :: map()
  def status(user_id), do: view(Homes.get(user_id).house, now())

  @doc "The same, from a stored house record (pure apart from config)."
  @spec view(map() | nil, integer()) :: map()
  def view(house, now) do
    st = state(house, now)
    started = if is_map(house), do: Map.get(house, "started_at"), else: nil

    left =
      if st == "building", do: max(0, started + build_ms() - now), else: 0

    %{
      state: st,
      started_at: started,
      build_ms: build_ms(),
      left_ms: left,
      wood: wood_cost(),
      coins: coin_cost()
    }
  end

  @doc """
  Commission the house: in one transaction, take `wood/0` wood and `coins/0` coins and start building.
  `{:ok, %{status, balance}}` or `{:error, reason}` with nothing moved: `:have_house`, `:not_enough` (the
  wood) or `:insufficient_funds`.
  """
  @spec commission(Ecto.UUID.t()) :: {:ok, map()} | {:error, atom()}
  def commission(user_id) do
    if Homes.get(user_id).house do
      {:error, :have_house}
    else
      correlation_id = Ecto.UUID.generate()

      opts = [
        txn_type: "commission",
        context: %{"what" => "house"},
        correlation_id: correlation_id
      ]

      now = now()

      Repo.transaction(fn ->
        case Economy.consume(user_id, Harvest.wood_id(), wood_cost(), opts) do
          {:ok, _left} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end

        balance =
          case Economy.sink_currency(user_id, "coins", coin_cost(), opts) do
            {:ok, b} -> b
            {:error, reason} -> Repo.rollback(reason)
          end

        house = %{"started_at" => now}
        Homes.set_house(user_id, house)
        %{status: view(house, now), balance: balance}
      end)
    end
  end

  @doc "Whether `pos` is at the carpenter (a prop with `\"builds\": \"house\"`)."
  @spec at_carpenter?(map() | nil, list() | nil) :: boolean()
  def at_carpenter?(core, [x, y]) when is_map(core) and is_number(x) and is_number(y) do
    props = Map.get(core, "props", [])

    is_list(props) and
      Enum.any?(props, fn p ->
        is_map(p) and Map.get(p, "builds") == "house" and near?(Map.get(p, "position"), x, y)
      end)
  end

  def at_carpenter?(_core, _pos), do: false

  defp near?([px, py], x, y) when is_number(px) and is_number(py),
    do: (x - px) * (x - px) + (y - py) * (y - py) <= @reach * @reach

  defp near?(_p, _x, _y), do: false

  @doc "The wall clock, in unix ms (what `started_at` is measured in)."
  def now, do: System.system_time(:millisecond)
end
