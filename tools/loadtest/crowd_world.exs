# SC-4 (docs/scaling-design.md): make (or refresh) a load-test-only CROWD world on a running server, so
# the bots can measure interest cells without touching any real world.
#
# Like probe.exs it joins the server's Erlang cluster as a second node and runs one call there: an upsert
# of a plain, unlisted world whose spec has a crowd block. Nothing in the repo seeds it, so it never ships
# and never shows in the Gateway. Prints the world id for the bots.
#
#   elixir --sname mkcrowd --cookie loadtest tools/loadtest/crowd_world.exs srv@$(hostname -s) [cell_px]
#
# The spawn sits in the MIDDLE of a cell (cell / 2, cell / 2), so a crowd gathered at the spawn is one cell.

[target | rest] = System.argv()
target = String.to_atom(target)
cell = String.to_integer(Enum.at(rest, 0, "480"))
world_id = "5c4c0bd0-0000-4000-8000-00000000c0de"

unless Node.connect(target) do
  IO.puts(:stderr, "crowd_world: could not connect to #{target} (is it running with --sname and the same --cookie?)")
  System.halt(1)
end

half = div(cell, 2)

core = %{
  "bounds" => [-20_000, -20_000, 20_000, 20_000],
  "player_spawn" => [half, half],
  "companion_spawn" => [half - 34, half + 26],
  "crowd" => %{"cell" => cell, "full" => 40, "lite" => 80},
  "fishing" => false,
  "chopping" => false
}

attrs = %{
  world_id: world_id,
  slug: "loadtest-crowd",
  name: "Load test crowd",
  display_types: ["2d"],
  version: 1,
  listed: false,
  spec: %{"core" => core, "profiles" => %{"2d" => %{}}}
}

case :erpc.call(target, Server.Worlds, :upsert, [attrs], 30_000) do
  {:ok, _} ->
    IO.puts(world_id)

  other ->
    IO.puts(:stderr, "crowd_world: upsert failed: #{inspect(other)}")
    System.halt(1)
end
