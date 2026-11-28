defmodule Server.LinkThrottle do
  @moduledoc """
  Slows down guessing at link codes (`POST /link/redeem`). Only FAILED redeems count: a wrong,
  expired or used code. A new device polling its own pending request is never counted.

  Two fixed ten-minute windows: one per remote IP (about 10 failures), and one for the whole server
  as a backstop, since behind a proxy every player can share one IP. A code is 8 characters from 31,
  so even the backstop leaves guessing hopeless. Counters live in a small public ETS table this
  process owns and sweeps; they're node-local, which only makes a multi-node server a little more
  generous.
  """
  use GenServer

  @table :link_throttle
  @window_ms 600_000
  @defaults [per_ip: 10, global: 200]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Whether this IP (or the whole server) has used up its failures for now."
  @spec limited?(term()) :: boolean()
  def limited?(ip) do
    w = window()
    count({:ip, ip, w}) >= limit(:per_ip) or count({:global, w}) >= limit(:global)
  end

  @doc "Count one failed redeem from this IP."
  @spec fail(term()) :: :ok
  def fail(ip) do
    w = window()
    :ets.update_counter(@table, {:ip, ip, w}, 1, {{:ip, ip, w}, 0})
    :ets.update_counter(@table, {:global, w}, 1, {{:global, w}, 0})
    :ok
  end

  @doc "Forget every count (tests)."
  def reset, do: :ets.delete_all_objects(@table)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  # Drop counters from windows that have passed.
  @impl true
  def handle_info(:sweep, state) do
    w = window()
    :ets.select_delete(@table, [{{{:ip, :_, :"$1"}, :_}, [{:<, :"$1", w}], [true]}])
    :ets.select_delete(@table, [{{{:global, :"$1"}, :_}, [{:<, :"$1", w}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @window_ms)

  defp window, do: div(System.system_time(:millisecond), @window_ms)

  defp count(key) do
    case :ets.lookup(@table, key) do
      [{_, n}] -> n
      [] -> 0
    end
  end

  defp limit(key) do
    Application.get_env(:server, __MODULE__, []) |> Keyword.get(key, @defaults[key])
  end
end
