defmodule Server.Wishes do
  @moduledoc """
  Lingerlong's WISHING FOUNTAIN: a shared ritual and a very small coin sink. A player standing by the fountain
  tosses a coin in (`wish` on the channel). It costs one coin when they have one; when they have none the wish
  is free (the fountain doesn't mind). Every wish adds to the fountain's count, which the world keeps for good.

  Built to hold a crowd:

    * the count lives in an ETS table (`{world_id, total, pending}`), so reading it and adding to it never wait
      on anything: `:ets.update_counter/3` from the player's own channel process. This process only loads a
      world's count once and writes the pending wishes to Postgres every `@flush_ms` (one upsert-increment per
      world with new wishes, `Server.WorldCounter`), and once more when it stops. A crash costs at most a couple
      of seconds of wishes, never a coin: the coin is spent in its own ledgered transaction;
    * a player may wish at most once per `@min_gap_ms` (the channel keeps the time on the socket, `allow?/2`);
    * the `wished` relay to the rest of the world is capped at `@relay_per_sec` a second per world
      (`relay?/2`). Past that the wish still counts and the wisher still sees their own coin (they get their own
      answer); the others just see the next relayed wish's count jump a little. So a crowd tossing coins as
      fast as they may costs every client at most a handful of tiny messages a second.

  Only worlds whose spec has a `fountain` block (`fountain/1`) have one; the check of where the player stands is
  the server's own last-known position for them (`near?/2`).
  """
  use GenServer
  require Logger
  import Ecto.Query, only: [from: 2]

  alias Server.{Economy, Repo, WorldCounter}

  @table :wishes
  @key "wishes"
  @min_gap_ms 1_500
  # How far past the basin's rim you may stand and still toss a coin in (px). Generous: the client offers it a
  # little nearer than this, so a step of lag never turns a wish away.
  @reach 110
  @relay_per_sec 8
  @flush_ms 2_000

  # ── The rules (pure) ────────────────────────────────────────────────────────────────────────────

  @doc "This world's fountain from its spec's core (`%{center: {x, y}, radius: r}`), or nil if it has none."
  @spec fountain(map() | nil) :: %{center: {number(), number()}, radius: number()} | nil
  def fountain(%{"fountain" => %{"center" => [x, y]} = f}) when is_number(x) and is_number(y) do
    r = Map.get(f, "radius", 0)
    %{center: {x, y}, radius: if(is_number(r), do: r, else: 0)}
  end

  def fountain(_), do: nil

  @doc "Whether `pos` (`[x, y]`) is close enough to the fountain to toss a coin in."
  @spec near?(map() | nil, list() | nil) :: boolean()
  def near?(%{center: {cx, cy}, radius: r}, [x, y]) when is_number(x) and is_number(y) do
    dx = x - cx
    dy = y - cy
    reach = r + @reach
    dx * dx + dy * dy <= reach * reach
  end

  def near?(_, _), do: false

  @doc "Whether a wish at `now_ms` is allowed, given the time of this player's last one (or nil)."
  @spec allow?(integer() | nil, integer()) :: boolean()
  def allow?(nil, _now_ms), do: true
  def allow?(last_ms, now_ms), do: now_ms - last_ms >= @min_gap_ms

  @doc "The shortest gap between one player's wishes, in ms."
  def min_gap_ms, do: @min_gap_ms

  @doc "How many wishes a second one world relays to everyone (the rest still count)."
  def relay_per_sec, do: @relay_per_sec

  # ── Making a wish ───────────────────────────────────────────────────────────────────────────────

  @doc """
  `user_id` tosses a coin into `world_id`'s fountain: one coin if they have one (ledgered, `txn_type` "wish"),
  free otherwise. Returns `%{n: total wishes, paid: boolean, balance: coins left}`. The caller has already
  checked the place and the pace.
  """
  @spec wish(Ecto.UUID.t(), String.t()) :: %{n: integer(), paid: boolean(), balance: integer()}
  def wish(user_id, world_id) do
    {paid, balance} =
      if Economy.balance(user_id, "coins") >= 1 do
        case Economy.sink_currency(user_id, "coins", 1, txn_type: "wish", context: %{"world" => world_id}) do
          {:ok, left} -> {true, left}
          # (spent elsewhere in the same instant: then this one is on the house)
          {:error, _} -> {false, Economy.balance(user_id, "coins")}
        end
      else
        {false, 0}
      end

    %{n: add(world_id), paid: paid, balance: balance}
  end

  # ── The count ───────────────────────────────────────────────────────────────────────────────────

  @doc "How many wishes `world_id`'s fountain holds (all time). Free after the first read."
  @spec count(String.t()) :: integer()
  def count(world_id) do
    case :ets.lookup(@table, world_id) do
      [{_, total, _pending}] -> total
      [] -> load(world_id)
    end
  end

  @doc "Add one wish to `world_id`'s count; returns the new total."
  @spec add(String.t()) :: integer()
  def add(world_id) do
    _ = count(world_id)
    [total, _pending] = :ets.update_counter(@table, world_id, [{2, 1}, {3, 1}])
    total
  end

  @doc """
  Whether this wish should go out to everyone else in `world_id`: true for the first `relay_per_sec/0` in any
  one second of `now_ms`, false after.
  """
  @spec relay?(String.t(), integer()) :: boolean()
  def relay?(world_id, now_ms) do
    key = {:relay, world_id, div(now_ms, 1000)}
    :ets.update_counter(@table, key, {2, 1}, {key, 0}) <= @relay_per_sec
  end

  @doc "Write every pending wish to Postgres now (tests; also done on a timer and on shutdown)."
  def flush, do: GenServer.call(__MODULE__, :flush)

  @doc "Forget the cached counts, so the next read comes from Postgres (tests)."
  def forget_cache, do: GenServer.call(__MODULE__, :forget)

  # Read a world's count from Postgres into the cache (racing readers: the first insert wins).
  defp load(world_id) do
    stored = Repo.one(from_counter(world_id)) || 0
    :ets.insert_new(@table, {world_id, stored, 0})
    [{_, total, _}] = :ets.lookup(@table, world_id)
    total
  end

  defp from_counter(world_id) do
    from(c in WorldCounter, where: c.world_id == ^world_id and c.key == ^@key, select: c.value)
  end

  # ── The process: owns the table, writes the count out ───────────────────────────────────────────

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    Process.flag(:trap_exit, true)
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true, write_concurrency: true])
    Process.send_after(self(), :flush, @flush_ms)
    {:ok, nil}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    write_pending()
    {:reply, :ok, state}
  end

  def handle_call(:forget, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:flush, state) do
    write_pending()
    # old relay buckets go too, so the table only holds counts and this second's relays
    now_s = div(System.system_time(:millisecond), 1000)
    :ets.select_delete(@table, [{{{:relay, :_, :"$1"}, :_}, [{:<, :"$1", now_s - 1}], [true]}])
    Process.send_after(self(), :flush, @flush_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, _state) do
    write_pending()
    :ok
  end

  defp write_pending do
    pending = :ets.select(@table, [{{:"$1", :_, :"$2"}, [{:is_binary, :"$1"}, {:>, :"$2", 0}], [{{:"$1", :"$2"}}]}])

    Enum.each(pending, fn {world_id, n} ->
      try do
        now = DateTime.utc_now()

        Repo.insert_all(
          WorldCounter,
          [%{world_id: world_id, key: @key, value: n, inserted_at: now, updated_at: now}],
          on_conflict: [inc: [value: n], set: [updated_at: now]],
          conflict_target: [:world_id, :key]
        )

        :ets.update_counter(@table, world_id, {3, -n})
      rescue
        # (the database briefly away: keep them pending, the next flush tries again)
        e -> Logger.warning("couldn't write the fountain's wishes: #{Exception.message(e)}")
      end
    end)
  end
end
