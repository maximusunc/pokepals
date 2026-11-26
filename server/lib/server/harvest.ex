defmodule Server.Harvest do
  @moduledoc """
  HARVESTING (home building, docs/usable-items-design.md "Home building"): the things you gather from the
  worlds, and the rules the channel judges a gather by.

    * **Trees.** With an **axe** on you, any tree in a world's spec `trees` can be chopped down, except in a
      world that opts out (`"chopping": false`: the Vale, and every home) and except growths that aren't
      wood (a fence picket, a crystal spire, a flower stalk; `@not_wood`). A tree gives `wood_per_tree`
      pieces of **wood** and grows back after `tree_regrow_ms`.
    * **Pickups.** Loose things lying about (a world spec's `pickups`: `%{"id", "kind", "position"}`), picked
      up with nothing in hand: **stones** and **driftwood** on the Riverbank. One each, back after
      `pickup_regrow_ms`.

  A felled tree or a taken pickup is gone **for everyone in that world** until it grows back: the shared
  state is kept here, in an ETS table owned by this process (`{world_id, node_id} => regrow_at`, monotonic
  ms), so it outlives a world process that stops when its last player leaves. It's forgotten on a server
  restart, which only means everything has grown back. Taking a node is a call into this process, so two
  players reaching for the same tree can't both have it.

  Chopping is instant for now. `chop_ms` (config) makes it take time: the client swings for that long, and
  the server then honours a chop only that long after the player said they'd started on that very tree.

  Tunables (`config :server, Server.Harvest`; see config.exs and runtime.exs): `tree_regrow_ms`,
  `pickup_regrow_ms`, `wood_per_tree`, `chop_ms`.
  """
  use GenServer

  alias Server.{ItemDefinition, Repo}

  @axe_id 11
  @stone_id 243
  @wood_id 244
  @driftwood_id 242

  # What a pickup's `kind` gives.
  @pickup_items %{"stone" => @stone_id, "driftwood" => @driftwood_id}

  # Tree kinds that aren't wood: a world's fence pickets (Thimblewick's gaps are its secret), grass and
  # flower stalks, crystal and glow growths, sweets, stone pillars and mounds, giant mushrooms, and
  # Glintwold's crystal spires, hills and boulders (its pines and round trees are wood).
  @not_wood ~w(picket grass clover daisy poppy cosmos dandelion foxglove bluebell crystal_spire bell_flower
               spore_stalk bubble_stalk lolli gumdrop pillar mound fungus gw_spire gw_hill gw_boulder)

  # How near a tree's trunk (or a pickup) you must stand. Generous: positions arrive at ~20 Hz and the
  # client stands you a body-width off the trunk.
  @tree_reach 60.0
  @pickup_reach 80.0

  @defaults [tree_regrow_ms: 300_000, pickup_regrow_ms: 180_000, wood_per_tree: 2, chop_ms: 0]

  @table :harvest_down

  # ── config ──

  defp cfg(key),
    do: Keyword.get(Application.get_env(:server, __MODULE__, []), key, @defaults[key])

  def tree_regrow_ms, do: cfg(:tree_regrow_ms)
  def pickup_regrow_ms, do: cfg(:pickup_regrow_ms)
  def wood_per_tree, do: cfg(:wood_per_tree)
  def chop_ms, do: cfg(:chop_ms)

  def axe_id, do: @axe_id
  def stone_id, do: @stone_id
  def wood_id, do: @wood_id

  # ── items ──

  @doc "The axe, the stone and the wood (driftwood is a fishing catch, defined with Server.Fishing)."
  def item_defs do
    [
      %{
        item_def_id: @axe_id,
        name: "Axe",
        category: "tool",
        slot: "hand",
        stackable: false,
        base_attributes: %{"key" => "axe", "use" => "chop", "color" => [0.66, 0.70, 0.74]}
      },
      %{
        item_def_id: @stone_id,
        name: "River Stone",
        category: "material",
        slot: nil,
        stackable: true,
        base_attributes: %{"key" => "stone", "color" => [0.62, 0.64, 0.66]}
      },
      %{
        item_def_id: @wood_id,
        name: "Wood",
        category: "material",
        slot: nil,
        stackable: true,
        base_attributes: %{"key" => "wood", "color" => [0.66, 0.46, 0.28]}
      }
    ]
  end

  @doc "Upsert harvesting's item definitions (idempotent)."
  def seed_definitions do
    for attrs <- item_defs() do
      %ItemDefinition{}
      |> ItemDefinition.changeset(attrs)
      |> Repo.insert!(
        on_conflict: {:replace, [:name, :category, :slot, :stackable, :base_attributes]},
        conflict_target: :item_def_id
      )
    end

    :ok
  end

  # ── the rules (pure) ──

  @doc "Whether a world lets you chop its trees (on unless its spec core says `\"chopping\": false`)."
  @spec chopping_allowed?(map() | nil) :: boolean()
  def chopping_allowed?(core) when is_map(core), do: Map.get(core, "chopping", true) != false
  def chopping_allowed?(_), do: false

  @doc "Whether a tree kind is wood (so it can be chopped)."
  @spec wood_kind?(String.t()) :: boolean()
  def wood_kind?(kind), do: kind not in @not_wood

  @doc "The tree at `index` in a spec core's `trees`, as `{x, y, kind}`, or nil."
  @spec tree(map(), integer()) :: {number(), number(), String.t()} | nil
  def tree(core, index) when is_map(core) and is_integer(index) and index >= 0 do
    case Enum.at(Map.get(core, "trees", []) || [], index) do
      [x, y] when is_number(x) and is_number(y) -> {x, y, "tree"}
      [x, y, k | _] when is_number(x) and is_number(y) and is_binary(k) -> {x, y, k}
      _ -> nil
    end
  end

  def tree(_core, _index), do: nil

  @doc "A tree's node id (what clients and the shared state call it): `\"t\" <> index`."
  def tree_node(index), do: "t" <> Integer.to_string(index)

  @doc "The pickup with this id in a spec core's `pickups`, or nil."
  @spec pickup(map(), String.t()) :: map() | nil
  def pickup(core, id) when is_map(core) and is_binary(id) do
    Enum.find(Map.get(core, "pickups", []) || [], fn p ->
      is_map(p) and Map.get(p, "id") == id and Map.has_key?(@pickup_items, Map.get(p, "kind"))
    end)
  end

  def pickup(_core, _id), do: nil

  @doc "What a pickup of this kind gives (an item definition id), or nil."
  def pickup_item(kind), do: Map.get(@pickup_items, kind)

  @doc """
  Whether `pos` ([x, y]) is near enough to chop tree `index` of this world: it exists, it's wood, the world
  allows chopping, and you're within reach of its trunk. `{:ok, {x, y, kind}}` or `{:error, reason}`.
  """
  @spec check_tree(map() | nil, integer(), list() | nil) :: {:ok, tuple()} | {:error, atom()}
  def check_tree(core, index, pos) do
    with true <- chopping_allowed?(core) || {:error, :no_chopping},
         {x, y, kind} = t <- tree(core, index) || {:error, :no_tree},
         true <- wood_kind?(kind) || {:error, :not_wood},
         true <- within?(pos, x, y, @tree_reach) || {:error, :too_far} do
      {:ok, t}
    end
  end

  @doc "Whether `pos` is near enough to pick up pickup `id`. `{:ok, pickup}` or `{:error, reason}`."
  @spec check_pickup(map() | nil, String.t(), list() | nil) :: {:ok, map()} | {:error, atom()}
  def check_pickup(core, id, pos) do
    with %{} = p <- pickup(core, id) || {:error, :no_pickup},
         [x, y] when is_number(x) and is_number(y) <-
           Map.get(p, "position") || {:error, :no_pickup},
         true <- within?(pos, x, y, @pickup_reach) || {:error, :too_far} do
      {:ok, p}
    end
  end

  @doc """
  Whether a timed chop is ripe: with `chop_ms` > 0 the player must have started on this very tree (`started`
  is `{node, monotonic_ms}` or nil) at least about `chop_ms` ago. Always true while chopping is instant.
  """
  @spec chop_ripe?({String.t(), integer()} | nil, String.t(), integer()) :: boolean()
  def chop_ripe?(started, node, now) do
    case chop_ms() do
      ms when ms <= 0 ->
        true

      ms ->
        case started do
          {^node, at} -> now - at >= ms - 250
          _ -> false
        end
    end
  end

  defp within?([px, py], x, y, r) when is_number(px) and is_number(py),
    do: (px - x) * (px - x) + (py - y) * (py - y) <= r * r

  defp within?(_pos, _x, _y, _r), do: false

  # ── the shared state (who has felled / taken what, until when) ──

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Take node `node` in `world_id` (fell a tree, pick something up) for `regrow_ms`. `:ok`, or `{:error,
  :gone}` if it's already down. Atomic: a call into this process.
  """
  @spec take(String.t(), String.t(), non_neg_integer()) :: :ok | {:error, :gone}
  def take(world_id, node, regrow_ms),
    do: GenServer.call(__MODULE__, {:take, world_id, node, regrow_ms})

  @doc "Whether node `node` in `world_id` is down right now."
  @spec down?(String.t(), String.t()) :: boolean()
  def down?(world_id, node) do
    now = now()

    case :ets.lookup(@table, {world_id, node}) do
      [{_, until}] -> until > now
      [] -> false
    end
  end

  @doc "Everything down in `world_id` right now: `[%{id, left_ms}]` (how long until each grows back)."
  @spec down(String.t()) :: [map()]
  def down(world_id) do
    now = now()

    @table
    |> :ets.match_object({{world_id, :_}, :_})
    |> Enum.filter(fn {_, until} -> until > now end)
    |> Enum.map(fn {{_, node}, until} -> %{id: node, left_ms: until - now} end)
    |> Enum.sort_by(& &1.id)
  end

  @doc "Grow everything back at once (tests)."
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(nil) do
    table = :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])
    Process.send_after(self(), :sweep, 60_000)
    {:ok, table}
  end

  @impl true
  def handle_call({:take, world_id, node, regrow_ms}, _from, table) do
    key = {world_id, node}
    now = now()

    case :ets.lookup(table, key) do
      [{_, until}] when until > now ->
        {:reply, {:error, :gone}, table}

      _ ->
        :ets.insert(table, {key, now + regrow_ms})
        {:reply, :ok, table}
    end
  end

  def handle_call(:reset, _from, table) do
    :ets.delete_all_objects(table)
    {:reply, :ok, table}
  end

  # Every minute, drop what has grown back, so the table only ever holds what's down.
  @impl true
  def handle_info(:sweep, table) do
    now = now()
    :ets.select_delete(table, [{{:_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
    Process.send_after(self(), :sweep, 60_000)
    {:noreply, table}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
