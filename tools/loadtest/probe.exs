# SC-1 (docs/scaling-design.md): watch a RUNNING server from the outside while the bots load it.
#
# It joins the server's Erlang cluster as a separate node (Erlang distribution: two BEAM VMs talking
# over a socket) and samples, once per interval, the numbers that tell us whether the server keeps up:
#   - scheduler utilisation: how busy the server's CPU cores are, averaged (1.0 = every core flat out),
#   - run queue: work waiting for a core (persistently > 0 means CPU-bound),
#   - each world process's MAILBOX: messages it hasn't handled yet (growing = it can't keep up),
#     and its reductions/s (a BEAM unit of work),
#   - the per-player relay processes' mailboxes (the channel, and the WebSocket connection that
#     writes to the network): total and worst,
#   - memory.
# No server code changes: start the server as a named node, e.g.
#   elixir --sname srv --cookie loadtest -S mix run --no-halt
# then run:
#   elixir --sname probe --cookie loadtest tools/loadtest/probe.exs srv@$(hostname -s) [interval_s] [samples]

[target | rest] = System.argv()
target = String.to_atom(target)
interval = String.to_integer(Enum.at(rest, 0, "2"))
samples = String.to_integer(Enum.at(rest, 1, "1000000"))

unless Node.connect(target) do
  IO.puts(:stderr, "probe: could not connect to #{target} (is it running with --sname and the same --cookie?)")
  System.halt(1)
end

rpc = fn m, f, a -> :erpc.call(target, m, f, a, 60_000) end

# One sample, evaluated ON the server in a single call (scanning thousands of processes one remote
# call at a time would itself be the slow part). Returns a plain map.
sample_code = """
interval = #{interval}
:erlang.system_flag(:scheduler_wall_time, true)
n_sched = :erlang.system_info(:schedulers_online)
wt = fn -> :erlang.statistics(:scheduler_wall_time) |> Enum.sort() |> Enum.take(n_sched) end
w1 = wt.()
Process.sleep(interval * 1000)
w2 = wt.()
{act, tot} = Enum.zip(w1, w2) |> Enum.reduce({0, 0}, fn {{_, a1, t1}, {_, a2, t2}}, {a, t} -> {a + a2 - a1, t + t2 - t1} end)
util = if tot > 0, do: act / tot, else: 0.0
worlds = for {_, pid, _, _} <- DynamicSupervisor.which_children(Server.WorldSupervisor), is_pid(pid),
             i <- [Process.info(pid, [:message_queue_len, :reductions])], i != nil, do: {pid, Map.new(i)}
# Per player there are two relay processes: the channel (Server.WorldChannel) and the WebSocket
# connection that writes to the network (Bandit's handler). Either one backing up means lag.
kinds = for pid <- Process.list(),
            {:dictionary, d} <- [Process.info(pid, :dictionary)],
            kind <- [(case Keyword.get(d, :"$initial_call") do
                       {Server.WorldChannel, _, _} -> :chan
                       {Bandit.DelegatingHandler, _, _} -> :sock
                       _ -> nil
                     end)],
            kind != nil,
            {:message_queue_len, q} <- [Process.info(pid, :message_queue_len)], do: {kind, q}
%{util: util, run_q: :erlang.statistics(:total_run_queue_lengths),
  worlds: Enum.map(worlds, fn {pid, i} -> {pid, i.message_queue_len, i.reductions} end),
  chans: for({:chan, q} <- kinds, do: q), socks: for({:sock, q} <- kinds, do: q), mem: :erlang.memory(:total)}
"""

IO.puts("probe: connected to #{target}; sampling every #{interval}s")
IO.puts("  time      util  run_q  worlds  world_mbox  world_kred/s  channels  chan_mbox_sum  chan_mbox_max  sock_mbox_sum  sock_mbox_max  mem_MB")

Enum.reduce(1..samples, %{}, fn _, prev_red ->
  {s, _} = rpc.(Code, :eval_string, [sample_code])
  w_mail = s.worlds |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)
  red_now = Map.new(s.worlds, fn {pid, _, r} -> {pid, r} end)
  w_kred = s.worlds |> Enum.map(fn {pid, _, r} -> r - Map.get(prev_red, pid, r) end) |> Enum.sum()

  IO.puts(
    Enum.join(
      [
        "  " <> (Time.utc_now() |> Time.truncate(:second) |> Time.to_string()),
        :erlang.float_to_binary(s.util * 1.0, decimals: 2) |> String.pad_leading(5),
        Integer.to_string(s.run_q) |> String.pad_leading(6),
        Integer.to_string(length(s.worlds)) |> String.pad_leading(7),
        Integer.to_string(w_mail) |> String.pad_leading(11),
        Integer.to_string(div(w_kred, interval * 1000)) |> String.pad_leading(13),
        Integer.to_string(length(s.chans)) |> String.pad_leading(9),
        Integer.to_string(Enum.sum(s.chans)) |> String.pad_leading(14),
        Integer.to_string(Enum.max(s.chans, fn -> 0 end)) |> String.pad_leading(14),
        Integer.to_string(Enum.sum(s.socks)) |> String.pad_leading(14),
        Integer.to_string(Enum.max(s.socks, fn -> 0 end)) |> String.pad_leading(14),
        Integer.to_string(div(s.mem, 1_048_576)) |> String.pad_leading(7)
      ],
      " "
    )
  )

  red_now
end)
