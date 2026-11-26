defmodule Server.Interest do
  @moduledoc """
  SC-4 (docs/scaling-design.md): the grid maths of interest cells. Pure functions, no state.

  A world whose spec carries a crowd block (`core.crowd`, e.g. `{"cell": 480, "full": 40, "lite": 80}`)
  is cut into `cell` x `cell` px squares. A player's cell is `{floor(px / cell), floor(py / cell)}` of
  the PLAYER position (not the companion's). A player hears about the players in the 3 x 3 cells around
  its own: its NEIGHBOURHOOD. `Server.World` uses this module to decide which cell bundles each moved
  player's entry goes into, and `Server.WorldChannel` uses it to keep its one cell subscription and to
  work out which cells came into view when its player changes cell.

  Positions are rounded to whole pixels before the cell is taken, exactly as `Server.WorldStates`
  stores them, so the channel (which reads the raw packet) and the world process (which reads the
  stored transform) always agree on a player's cell.
  """

  @type cell :: {integer(), integer()}

  # Below this a cell is smaller than a screen and the topics multiply for no gain; a spec asking for
  # less is treated as having no crowd block.
  @min_cell 32
  @limit 1.0e6

  @doc """
  The interest config of a world from its spec's `core` map: `%{cell: size}`, or `nil` for a world
  with no (or an unusable) crowd block, which then behaves exactly as before SC-4.
  """
  @spec config(term()) :: %{cell: pos_integer()} | nil
  def config(%{"crowd" => %{"cell" => size}}) when is_number(size) and size >= @min_cell,
    do: %{cell: round(size)}

  def config(_), do: nil

  @doc "The cell of a position (`[x, y]` or `{x, y}`) for a grid of `size` px."
  @spec cell_of([number()] | {number(), number()}, pos_integer()) :: cell()
  def cell_of([x, y], size), do: cell_of({x, y}, size)
  def cell_of({x, y}, size), do: {floor_div(round(x), size), floor_div(round(y), size)}

  @doc """
  The cell of a transform's player position (`"p"`), read the way `Server.WorldStates.sanitize/1`
  reads it (a pair of finite numbers within range, rounded). `nil` when there's no usable position.
  """
  @spec cell_for(term(), pos_integer()) :: cell() | nil
  def cell_for(%{"p" => [x, y]}, size) when is_number(x) and is_number(y) do
    if abs(x) <= @limit and abs(y) <= @limit, do: cell_of({x, y}, size), else: nil
  end

  def cell_for(_, _), do: nil

  @doc "The 3 x 3 block of cells around `cell` (itself included)."
  @spec neighbourhood(cell()) :: [cell()]
  def neighbourhood({cx, cy}) do
    for dx <- -1..1, dy <- -1..1, do: {cx + dx, cy + dy}
  end

  @doc "Whether two cells are within each other's neighbourhood (Chebyshev distance at most 1)."
  @spec near?(cell(), cell()) :: boolean()
  def near?({ax, ay}, {bx, by}), do: abs(ax - bx) <= 1 and abs(ay - by) <= 1

  @doc """
  The cells that come into view when a player moves from `old` to `new`: the new neighbourhood minus
  the old one. From `nil` (no cell yet) it's the whole new neighbourhood; with no move, nothing.
  """
  @spec newly_visible(cell() | nil, cell()) :: [cell()]
  def newly_visible(nil, new), do: neighbourhood(new)
  def newly_visible(old, new), do: Enum.reject(neighbourhood(new), &near?(&1, old))

  @doc """
  Group moved players' entries into one bundle per subscriber cell.

  `moved` is a list of `{entry, cells}`, where `cells` are the player's cell now and, if it changed
  this tick, the cell it left (a list of one or two cells; an empty list means the player has no cell
  and is sent nowhere). `occupied` is a map whose KEYS are the cells someone stands in (the world's
  `%{cell => members}`). An entry goes to every occupied cell in the neighbourhood of any of its cells,
  at most once per cell. Returns `%{cell => [entry]}`, with only cells that got something.
  """
  @spec group([{term(), [cell()]}], map()) :: %{optional(cell()) => [term()]}
  def group(moved, occupied) do
    Enum.reduce(moved, %{}, fn {entry, cells}, acc ->
      targets =
        case cells do
          [cell] -> neighbourhood(cell)
          cells -> cells |> Enum.flat_map(&neighbourhood/1) |> Enum.uniq()
        end

      Enum.reduce(targets, acc, fn c, acc ->
        if Map.has_key?(occupied, c), do: Map.update(acc, c, [entry], &[entry | &1]), else: acc
      end)
    end)
  end

  @doc "The PubSub topic a cell's bundles go out on, for subscribers standing in that cell."
  @spec topic(String.t(), cell()) :: String.t()
  def topic(world_id, {cx, cy}), do: "world:#{world_id}:cell:#{cx},#{cy}"

  defp floor_div(a, b), do: Integer.floor_div(a, b)
end
