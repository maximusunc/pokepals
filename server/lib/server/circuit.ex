defmodule Server.Circuit do
  @moduledoc """
  The RIBBON BOARDS of Ohmstead (docs/home-world-and-secrets-design.md, "Ohmstead"): the shared,
  server-authoritative state of every board in a world whose spec has a `circuits` block. A board is a lattice
  of nodes; companions lay one ribbon of light through it, node by node; the rules are `Server.Circuit.Board`.

  Three kinds of board (the spec's `circuits.boards[].kind`):

    * `fixed`: authored in the spec (holes, source, sink). The dark sector, whose closing is Ohmstead's secret.
      Once closed it stays lit for `relight_s`, then loses its power again so the next visitor can close it.
    * `dealt`: the Arcade's table. Dealt here from a seed; `deal_s` after it is closed, a fresh one is dealt.
    * `daily`: the Arcade's board of the day. Dealt from the date (UTC), so it is the same board for everyone;
      once closed it stays closed until the day turns.

  The ribbon is SHARED: everyone in the world sees the same one, and anyone's companion may carry it on from its
  head, so friends close a board together. The client tells us which node its companion has reached; we judge
  the move by the rules and tell the whole world the result. (We take the client's word that its companion is
  there: companions live on the client. The rules are still ours, so no board can be closed that isn't.)

  State lives in this process, keyed by `{world_id, board_id}`, so it outlives a world process that stops when
  its last player leaves, and two players reaching for the same node can't both have it. It is forgotten on a
  server restart, which only means every ribbon is unlaid. A ribbon nobody has touched for `@stale_ms` is
  cleared, so a board is never left half-done for the next person.

  Closing a `dealt` or `daily` board pays everyone who laid part of its ribbon (`reward/2`, from the spec,
  capped here); the channel does the granting.
  """
  use GenServer

  alias Server.Circuit.Board
  alias Server.{ItemDefinition, Repo}

  @spark_id 260
  @stale_ms 300_000
  @tick_ms 30_000
  @max_coins 50
  @max_sparks 5

  def spark_id, do: @spark_id

  @doc "The spark: what the Arcade pays in, besides coins. A material found only in Ohmstead."
  def item_defs do
    [
      %{
        item_def_id: @spark_id,
        name: "Spark",
        category: "material",
        slot: nil,
        stackable: true,
        base_attributes: %{"key" => "spark", "color" => [1.0, 0.96, 0.82]}
      }
    ]
  end

  @doc "Upsert the circuit's item definitions (idempotent)."
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

  # ── the spec ──

  @doc "A world spec's `circuits` block, or nil if it has none."
  @spec config(map() | nil) :: map() | nil
  def config(%{"circuits" => %{"boards" => boards} = c}) when is_list(boards) and boards != [], do: c
  def config(_core), do: nil

  @doc "What closing board `board_id` pays each person who laid part of it: `{coins, sparks}`, capped."
  @spec reward(map() | nil, String.t()) :: {non_neg_integer(), non_neg_integer()}
  def reward(%{"reward" => rewards}, board_id) when is_map(rewards) do
    r = Map.get(rewards, board_id, %{})
    {clamp(r["coins"], @max_coins), clamp(r["sparks"], @max_sparks)}
  end

  def reward(_circuits, _board_id), do: {0, 0}

  defp clamp(n, max) when is_integer(n), do: n |> max(0) |> min(max)
  defp clamp(_n, _max), do: 0

  # ── the shared state ──

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Every board of `world_id` as the client sees it (made on first asking), for a join."
  @spec snapshot(String.t(), map() | nil) :: [map()]
  def snapshot(_world_id, nil), do: []
  def snapshot(world_id, circuits), do: GenServer.call(__MODULE__, {:snapshot, world_id, circuits})

  @doc """
  `user_id`'s companion has reached `node` of `board_id`: run the ribbon there. `{:ok, view, :extended}`,
  `{:ok, view, {:closed, %{by: [user_id], time_ms: ms, kind: kind}}}` when that closes the board, or
  `{:error, reason}` (`:no_board`, `:closed`, `:no_run`).
  """
  def run(world_id, circuits, board_id, node, user_id),
    do: GenServer.call(__MODULE__, {:run, world_id, circuits, board_id, node, user_id})

  @doc "Wind the ribbon of `board_id` back to `node`. `{:ok, view}` or `{:error, reason}`."
  def wind(world_id, circuits, board_id, node),
    do: GenServer.call(__MODULE__, {:wind, world_id, circuits, board_id, node})

  @doc "Put the ribbon of `board_id` out. Only someone who laid part of it may. `{:ok, view}` or `{:error, reason}`."
  def clear(world_id, circuits, board_id, user_id),
    do: GenServer.call(__MODULE__, {:clear, world_id, circuits, board_id, user_id})

  @doc "Whether `board_id` of `world_id` is closed right now (the secret's check)."
  @spec closed?(String.t(), String.t()) :: boolean()
  def closed?(world_id, board_id), do: GenServer.call(__MODULE__, {:closed?, world_id, board_id})

  @doc "Forget every board (tests)."
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(nil) do
    Process.send_after(self(), :tick, @tick_ms)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:snapshot, world_id, circuits}, _from, state) do
    state = ensure(state, world_id, circuits)
    views = for b <- boards(circuits), e = state[{world_id, b["id"]}], e != nil, do: view(e)
    {:reply, views, state}
  end

  def handle_call({:run, world_id, circuits, board_id, node, user_id}, _from, state) do
    state = ensure(state, world_id, circuits)

    with %{} = e <- state[{world_id, board_id}] || {:error, :no_board},
         false <- e.closed_ms != nil && {:error, :closed},
         [_ | _] = lit <- Board.run_to(e.board, node) || {:error, :no_run} do
      now = now()
      board = Board.extend(e.board, lit)

      e = %{
        e
        | board: board,
          laid: e.laid ++ List.duplicate(user_id, length(lit)),
          started_ms: e.started_ms || now,
          last_ms: now,
          seq: e.seq + 1
      }

      if Board.closed?(board) do
        e = %{e | closed_ms: now, time_ms: now - e.started_ms}
        after_closed(e)
        info = %{by: Enum.uniq(e.laid), time_ms: e.time_ms, kind: e.kind}
        {:reply, {:ok, view(e), {:closed, info}}, Map.put(state, {world_id, board_id}, e)}
      else
        {:reply, {:ok, view(e), :extended}, Map.put(state, {world_id, board_id}, e)}
      end
    else
      [] -> {:reply, {:error, :no_run}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:wind, world_id, circuits, board_id, node}, _from, state) do
    state = ensure(state, world_id, circuits)

    with %{} = e <- state[{world_id, board_id}] || {:error, :no_board},
         false <- e.closed_ms != nil && {:error, :closed},
         {:ok, board} <- Board.wind_to(e.board, node) do
      e = unlaid(%{e | board: board, laid: Enum.take(e.laid, length(board.path)), last_ms: now(), seq: e.seq + 1})
      {:reply, {:ok, view(e)}, Map.put(state, {world_id, board_id}, e)}
    else
      :error -> {:reply, {:error, :not_lit}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:clear, world_id, circuits, board_id, user_id}, _from, state) do
    state = ensure(state, world_id, circuits)

    with %{} = e <- state[{world_id, board_id}] || {:error, :no_board},
         false <- e.closed_ms != nil && {:error, :closed},
         true <- user_id in e.laid || {:error, :not_yours} do
      e = cleared(e)
      {:reply, {:ok, view(e)}, Map.put(state, {world_id, board_id}, e)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:closed?, world_id, board_id}, _from, state) do
    closed =
      case state[{world_id, board_id}] do
        %{closed_ms: ms} when ms != nil -> true
        _ -> false
      end

    {:reply, closed, state}
  end

  def handle_call(:reset, _from, _state), do: {:reply, :ok, %{}}

  # The Arcade's table: a fresh board, a little after the last one was closed.
  @impl true
  def handle_info({:deal, key, seq}, state) do
    case state[key] do
      %{kind: "dealt", seq: ^seq} = e ->
        e = deal(%{e | n: e.n + 1})
        announce(e)
        {:noreply, Map.put(state, key, e)}

      _ ->
        {:noreply, state}
    end
  end

  # The dark sector: its power is lost again, so the next visitor can close it.
  def handle_info({:relight_over, key, seq}, state) do
    case state[key] do
      %{kind: "fixed", seq: ^seq} = e ->
        e = %{cleared(e) | closed_ms: nil, time_ms: nil}
        announce(e)
        {:noreply, Map.put(state, key, e)}

      _ ->
        {:noreply, state}
    end
  end

  # Every so often: a new day brings a new daily board, and a ribbon nobody has touched for a while goes out.
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    today = Date.utc_today()
    now = now()

    state =
      Map.new(state, fn {key, e} ->
        cond do
          e.kind == "daily" and e.day != today ->
            e = deal(e)
            announce(e)
            {key, e}

          e.closed_ms == nil and e.board.path != [] and now - e.last_ms > @stale_ms ->
            e = cleared(e)
            announce(e)
            {key, e}

          true ->
            {key, e}
        end
      end)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── making and changing boards ──

  defp boards(%{"boards" => boards}) when is_list(boards),
    do: Enum.filter(boards, &(is_map(&1) and is_binary(&1["id"])))

  defp boards(_), do: []

  # Make any board of this world we don't hold yet; a daily one from another day is dealt afresh.
  defp ensure(state, world_id, circuits) do
    today = Date.utc_today()

    Enum.reduce(boards(circuits), state, fn cfg, acc ->
      key = {world_id, cfg["id"]}

      case acc[key] do
        nil -> Map.put(acc, key, fresh(world_id, cfg))
        %{kind: "daily", day: day} = e when day != today -> Map.put(acc, key, deal(e))
        _ -> acc
      end
    end)
  end

  defp fresh(world_id, cfg) do
    kind = if cfg["kind"] in ["fixed", "dealt", "daily"], do: cfg["kind"], else: "fixed"

    e = %{
      world_id: world_id,
      id: cfg["id"],
      kind: kind,
      cols: dim(cfg["cols"]),
      rows: dim(cfg["rows"]),
      hole_count: if(is_integer(cfg["holes"]), do: cfg["holes"], else: 0),
      relight_ms: seconds(cfg["relight_s"], 600) * 1000,
      deal_ms: seconds(cfg["deal_s"], 5) * 1000,
      board: nil,
      laid: [],
      started_ms: nil,
      closed_ms: nil,
      time_ms: nil,
      last_ms: now(),
      seq: 0,
      # the table starts somewhere different after each restart, so it isn't the same run of boards every time
      n: if(kind == "dealt", do: :erlang.unique_integer([:positive]) + rem(System.system_time(:second), 100_000), else: 0),
      day: nil
    }

    case kind do
      "fixed" -> %{e | board: Board.new(Map.merge(cfg, %{"cols" => e.cols, "rows" => e.rows, "path" => []}))}
      _ -> deal(e)
    end
  end

  defp dim(n) when is_integer(n), do: n |> max(2) |> min(9)
  defp dim(_n), do: 4

  defp seconds(n, _default) when is_number(n) and n >= 0, do: round(n)
  defp seconds(_n, default), do: default

  # A new board for a dealt or daily entry: the table's from its deal number, the day's from the date.
  defp deal(%{kind: "daily"} = e) do
    today = Date.utc_today()
    seed = {today.year, today.month * 100 + today.day, :erlang.phash2({e.world_id, e.id})}
    put_board(%{e | day: today}, seed)
  end

  defp deal(e), do: deal_fresh(e, 6)

  # Small boards have only so many layouts, so now and then a seed deals the one that was just played:
  # take the next seed instead (a few tries; after that, the same board again is fine).
  defp deal_fresh(e, tries) do
    dealt = put_board(e, {e.n, :erlang.phash2({e.world_id, e.id}), 7})

    same? =
      e.board != nil and
        {dealt.board.holes, dealt.board.source, dealt.board.sink} == {e.board.holes, e.board.source, e.board.sink}

    if same? and tries > 0, do: deal_fresh(%{e | n: e.n + 1}, tries - 1), else: dealt
  end

  defp put_board(e, seed) do
    g = Board.generate(e.cols, e.rows, e.hole_count, seed)

    board =
      Board.new(%{"cols" => e.cols, "rows" => e.rows, "holes" => g.holes, "source" => g.source, "sink" => g.sink})

    %{e | board: board, laid: [], started_ms: nil, closed_ms: nil, time_ms: nil, last_ms: now(), seq: e.seq + 1}
  end

  defp cleared(e),
    do: %{e | board: %{e.board | path: []}, laid: [], started_ms: nil, last_ms: now(), seq: e.seq + 1}

  defp unlaid(%{board: %{path: []}} = e), do: %{e | started_ms: nil}
  defp unlaid(e), do: e

  defp after_closed(%{kind: "dealt"} = e),
    do: Process.send_after(self(), {:deal, {e.world_id, e.id}, e.seq}, e.deal_ms)

  defp after_closed(%{kind: "fixed"} = e),
    do: Process.send_after(self(), {:relight_over, {e.world_id, e.id}, e.seq}, e.relight_ms)

  defp after_closed(_e), do: :ok

  # Tell everyone in the board's world how it stands now (for changes nobody's message caused).
  defp announce(e), do: Server.Endpoint.broadcast("world:" <> e.world_id, "circuit", view(e))

  @doc false
  def view(e) do
    %{
      id: e.id,
      kind: e.kind,
      cols: e.cols,
      rows: e.rows,
      holes: e.board.holes |> MapSet.to_list() |> Enum.sort(),
      source: e.board.source,
      sink: e.board.sink,
      path: e.board.path,
      closed: e.closed_ms != nil,
      seq: e.seq,
      time_ms: e.time_ms,
      by: Enum.uniq(e.laid),
      day: if(e.day, do: Date.to_iso8601(e.day), else: nil)
    }
  end

  defp now, do: System.monotonic_time(:millisecond)
end
