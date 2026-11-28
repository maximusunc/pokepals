defmodule Server.CircuitTest do
  @moduledoc """
  Ohmstead's ribbon boards: the rules (Server.Circuit.Board, held to the same vectors as the client's
  CircuitBoard), dealing a board that can always be closed, and the shared state (Server.Circuit). The channel
  side is in circuit_channel_test.
  """
  use ExUnit.Case, async: false

  alias Server.Circuit
  alias Server.Circuit.Board

  # The SAME vectors the client's CircuitBoard is held to (gates-of-elyra/tests/world_fixtures/circuit_vectors.json):
  # if these ever disagree, the client and the server no longer play the same game.
  @vectors Path.join([__DIR__, "fixtures", "circuit_vectors.json"]) |> File.read!() |> Jason.decode!()

  @sector %{"id" => "sector", "kind" => "fixed", "cols" => 5, "rows" => 4, "holes" => [15, 16], "source" => 10, "sink" => 17, "relight_s" => 600}
  @solution [10, 11, 6, 5, 0, 1, 2, 7, 12, 13, 8, 3, 4, 9, 14, 19, 18, 17]
  @circuits %{
    "boards" => [
      @sector,
      %{"id" => "table", "kind" => "dealt", "cols" => 5, "rows" => 4, "holes" => 2, "deal_s" => 5},
      %{"id" => "today", "kind" => "daily", "cols" => 7, "rows" => 4, "holes" => 3}
    ],
    "reward" => %{"table" => %{"coins" => 5, "sparks" => 1}, "today" => %{"coins" => 999, "sparks" => 99}}
  }

  setup do
    Circuit.reset()
    :ok
  end

  describe "the rules" do
    test "runs, winds and closing agree with the shared vectors" do
      for c <- @vectors["cases"] do
        Enum.reduce(c["steps"], Board.new(c["board"]), fn s, b ->
          b =
            case s["op"] do
              "run" ->
                lit = Board.run_to(b, s["node"])
                assert lit == s["lit"], "#{c["name"]}: run to #{s["node"]}"
                Board.extend(b, lit)

              "wind" ->
                case Board.wind_to(b, s["node"]) do
                  {:ok, wound} ->
                    assert s["ok"], "#{c["name"]}: wind to #{s["node"]}"
                    wound

                  :error ->
                    refute s["ok"], "#{c["name"]}: wind to #{s["node"]}"
                    b
                end
            end

          assert b.path == s["path"], "#{c["name"]}: path after #{s["op"]} #{s["node"]}"
          assert Board.closed?(b) == s["closed"], "#{c["name"]}: closed after #{s["op"]} #{s["node"]}"
          b
        end)
      end
    end

    test "a dealt board can always be closed, its ends are on the edge, and a seed always deals the same board" do
      for seed <- 1..40, {cols, rows, holes} <- [{5, 4, 2}, {7, 5, 3}, {3, 3, 0}] do
        g = Board.generate(cols, rows, holes, {seed, 11, 7})
        assert length(g.holes) == holes
        assert g.source != g.sink
        assert g == Board.generate(cols, rows, holes, {seed, 11, 7})

        for i <- [g.source, g.sink] do
          {c, r} = {rem(i, cols), div(i, cols)}
          assert c == 0 or r == 0 or c == cols - 1 or r == rows - 1
        end

        board = Board.new(%{"cols" => cols, "rows" => rows, "holes" => g.holes, "source" => g.source, "sink" => g.sink})
        assert closable?(board), "seed #{seed} #{cols}x#{rows} can be closed"
      end

      assert Board.generate(5, 4, 2, {1, 11, 7}) != Board.generate(5, 4, 2, {2, 11, 7})
    end
  end

  # A plain depth-first search for one stroke through every node from the source to the sink.
  defp closable?(board), do: search(Board.extend(board, [board.source]))

  defp search(board) do
    Board.closed?(board) or
      board.path
      |> List.last()
      |> Board.neighbours(board.cols, board.rows)
      |> Enum.any?(fn n ->
        case Board.run_to(board, n) do
          [] -> false
          lit -> search(Board.extend(board, lit))
        end
      end)
  end

  describe "the shared state" do
    test "a world's boards are made on first asking: the authored one as written, the others dealt" do
      views = Circuit.snapshot("w", @circuits)
      assert [%{id: "sector"} = sector, %{id: "table"} = table, %{id: "today"} = today] = views
      assert %{kind: "fixed", cols: 5, rows: 4, holes: [15, 16], source: 10, sink: 17, path: [], closed: false} = sector
      assert %{kind: "dealt", cols: 5, rows: 4, path: [], closed: false} = table
      assert length(table.holes) == 2
      assert %{kind: "daily", cols: 7, rows: 4} = today
      assert today.day == Date.to_iso8601(Date.utc_today())
      # asking again changes nothing
      assert Circuit.snapshot("w", @circuits) == views
      assert Circuit.snapshot("w", nil) == []
    end

    test "today's board is the same in every world of the same id, and differs from the table's" do
      [_, table, today] = Circuit.snapshot("w", @circuits)
      Circuit.reset()
      [_, _, again] = Circuit.snapshot("w", @circuits)
      assert {again.holes, again.source, again.sink} == {today.holes, today.source, today.sink}
      refute {table.cols, table.holes} == {today.cols, today.holes}
    end

    test "anyone may carry the ribbon on; closing it reports who laid it and how long it took" do
      {first, rest} = Enum.split(@solution, 9)

      for n <- first do
        assert {:ok, %{closed: false}, :extended} = Circuit.run("w", @circuits, "sector", n, "ann")
      end

      {last, middle} = List.pop_at(rest, -1)

      for n <- middle do
        assert {:ok, _view, :extended} = Circuit.run("w", @circuits, "sector", n, "bo")
      end

      refute Circuit.closed?("w", "sector")
      assert {:ok, view, {:closed, info}} = Circuit.run("w", @circuits, "sector", last, "bo")
      assert view.closed and view.path == @solution and view.by == ["ann", "bo"]
      assert info.by == ["ann", "bo"] and info.kind == "fixed" and info.time_ms >= 0
      assert Circuit.closed?("w", "sector")
      # a closed board takes no more moves
      assert {:error, :closed} = Circuit.run("w", @circuits, "sector", 10, "ann")
      assert {:error, :closed} = Circuit.wind("w", @circuits, "sector", 10)
      # other worlds are untouched
      refute Circuit.closed?("other", "sector")
    end

    test "what is refused: a move the rules don't allow, a board that isn't there" do
      assert {:error, :no_run} = Circuit.run("w", @circuits, "sector", 0, "ann")
      assert {:error, :no_board} = Circuit.run("w", @circuits, "nope", 0, "ann")
      assert {:ok, _, :extended} = Circuit.run("w", @circuits, "sector", 10, "ann")
      assert {:error, :no_run} = Circuit.run("w", @circuits, "sector", 6, "ann")
      assert {:error, :not_lit} = Circuit.wind("w", @circuits, "sector", 3)
    end

    test "winding back, and putting the ribbon out (only by someone who laid part of it)" do
      assert {:ok, %{path: [10]}, :extended} = Circuit.run("w", @circuits, "sector", 10, "ann")
      assert {:ok, %{path: [10, 11, 12, 13, 14]}, :extended} = Circuit.run("w", @circuits, "sector", 14, "bo")
      assert {:ok, %{path: [10, 11, 12], by: ["ann", "bo"]}} = Circuit.wind("w", @circuits, "sector", 12)
      assert {:ok, %{path: [10, 11], seq: seq}} = Circuit.wind("w", @circuits, "sector", 12)
      assert {:error, :not_yours} = Circuit.clear("w", @circuits, "sector", "cy")
      assert {:ok, %{path: [], by: [], seq: after_clear}} = Circuit.clear("w", @circuits, "sector", "bo")
      assert after_clear > seq
    end

    test "the dark sector loses its power again after a while, so the next visitor can close it" do
      for n <- @solution, do: Circuit.run("w", @circuits, "sector", n, "ann")
      assert Circuit.closed?("w", "sector")
      [%{seq: seq} | _] = Circuit.snapshot("w", @circuits)
      send(Circuit, {:relight_over, {"w", "sector"}, seq - 1})
      assert Circuit.closed?("w", "sector"), "a stale timer changes nothing"
      assert Circuit.claimable?("w", "sector")
      send(Circuit, {:relight_over, {"w", "sector"}, seq})
      refute Circuit.closed?("w", "sector")
      # ...but a claim made as the lights went down is still good for a few seconds
      assert Circuit.claimable?("w", "sector")
      refute Circuit.claimable?("w", "table")
      refute Circuit.claimable?("elsewhere", "sector")
      assert [%{path: [], closed: false} | _] = Circuit.snapshot("w", @circuits)
    end

    test "the table deals a new board after one is closed" do
      [_, table, _] = Circuit.snapshot("w", @circuits)
      board = Board.new(%{"cols" => 5, "rows" => 4, "holes" => table.holes, "source" => table.source, "sink" => table.sink})
      for n <- solve(board), do: Circuit.run("w", @circuits, "table", n, "ann")
      assert Circuit.closed?("w", "table")
      [_, %{seq: seq, closed: true}, _] = Circuit.snapshot("w", @circuits)
      send(Circuit, {:deal, {"w", "table"}, seq})
      [_, dealt, _] = Circuit.snapshot("w", @circuits)
      assert %{closed: false, path: []} = dealt
      refute {dealt.holes, dealt.source, dealt.sink} == {table.holes, table.source, table.sink}
    end

    test "what a board pays comes from the spec, capped" do
      assert Circuit.reward(@circuits, "table") == {5, 1}
      assert Circuit.reward(@circuits, "today") == {50, 5}
      assert Circuit.reward(@circuits, "sector") == {0, 0}
      assert Circuit.reward(nil, "table") == {0, 0}
    end
  end

  @doc false
  def solve(board), do: tl_or_all(find(Board.extend(board, [board.source])))

  defp tl_or_all(path), do: path

  defp find(board) do
    if Board.closed?(board) do
      board.path
    else
      board.path
      |> List.last()
      |> Board.neighbours(board.cols, board.rows)
      |> Enum.find_value(fn n ->
        case Board.run_to(board, n) do
          [] -> nil
          lit -> find(Board.extend(board, lit))
        end
      end)
    end
  end
end
