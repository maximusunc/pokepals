defmodule Server.Circuit.Board do
  @moduledoc """
  One RIBBON BOARD (Ohmstead): a lattice of nodes, some missing, and one ribbon of light that has to be laid
  through every node that is there, from the `source` (where a live line comes in) to the `sink` (the outlet).
  The twin of the client's `CircuitBoard` (pokepals/scripts/world/circuit_board.gd), held to the same test
  vectors (test/fixtures/circuit_vectors.json).

  The rules:

    * a node's index is `row * cols + col`; `holes` are indices with no node;
    * the ribbon (`path`) starts on the source and nowhere else;
    * from its head it runs STRAIGHT along a row or a column to the node named, lighting every node it passes;
      none of them may be a hole or already lit (so a ribbon never crosses or touches itself);
    * naming a lit node winds the ribbon back to it; naming the head itself takes one node off;
    * the board is CLOSED when every node is lit and the head is on the sink.

  Pure. `generate/4` makes a board that can always be closed (it is built from a path through every node).
  """

  defstruct cols: 1, rows: 1, holes: MapSet.new(), source: 0, sink: 0, path: []

  @type t :: %__MODULE__{}

  @doc "A board from a map with string keys: cols, rows, holes (a list), source, sink, and optionally path."
  @spec new(map()) :: t()
  def new(%{} = m) do
    %__MODULE__{
      cols: max(1, int(m["cols"], 1)),
      rows: max(1, int(m["rows"], 1)),
      holes: m |> Map.get("holes", []) |> List.wrap() |> Enum.filter(&is_integer/1) |> MapSet.new(),
      source: int(m["source"], 0),
      sink: int(m["sink"], 0),
      path: m |> Map.get("path", []) |> List.wrap() |> Enum.filter(&is_integer/1)
    }
  end

  defp int(v, _default) when is_integer(v), do: v
  defp int(_v, default), do: default

  @doc "Whether `i` is a node of this board (on the lattice, and not a hole)."
  def node?(%__MODULE__{} = b, i),
    do: is_integer(i) and i >= 0 and i < b.cols * b.rows and not MapSet.member?(b.holes, i)

  @doc "How many nodes the board has."
  def live_count(%__MODULE__{} = b), do: b.cols * b.rows - MapSet.size(b.holes)

  @doc "The nodes a ribbon run to `node` would light, in order (`[]` if the run isn't allowed)."
  @spec run_to(t(), integer()) :: [integer()]
  def run_to(%__MODULE__{} = b, node) do
    cond do
      not node?(b, node) or node in b.path -> []
      b.path == [] -> if node == b.source, do: [node], else: []
      true -> straight(b, List.last(b.path), node)
    end
  end

  defp straight(b, head, node) do
    {hc, hr} = {rem(head, b.cols), div(head, b.cols)}
    {nc, nr} = {rem(node, b.cols), div(node, b.cols)}

    step =
      cond do
        hr == nr -> if nc > hc, do: 1, else: -1
        hc == nc -> if nr > hr, do: b.cols, else: -b.cols
        true -> 0
      end

    if step == 0, do: [], else: walk(b, head + step, node, step, [])
  end

  defp walk(b, i, node, step, acc) do
    cond do
      not node?(b, i) or i in b.path -> []
      i == node -> Enum.reverse([i | acc])
      true -> walk(b, i + step, node, step, [i | acc])
    end
  end

  @doc "Light `nodes` (as `run_to/2` returned them)."
  def extend(%__MODULE__{} = b, nodes), do: %{b | path: b.path ++ nodes}

  @doc "Wind the ribbon back so `node` is its head (the head itself: one node comes off). `:error` if it isn't lit."
  @spec wind_to(t(), integer()) :: {:ok, t()} | :error
  def wind_to(%__MODULE__{} = b, node) do
    case Enum.find_index(b.path, &(&1 == node)) do
      nil ->
        :error

      at ->
        keep = if at == length(b.path) - 1, do: at, else: at + 1
        {:ok, %{b | path: Enum.take(b.path, keep)}}
    end
  end

  @doc "Every node lit, and the head on the sink."
  def closed?(%__MODULE__{path: []}), do: false

  def closed?(%__MODULE__{} = b),
    do: length(b.path) == live_count(b) and List.last(b.path) == b.sink

  # ── dealing a board ──

  @doc """
  A board of `cols` x `rows` with `holes` nodes missing, from `seed` (a three-integer tuple): `%{holes: [..],
  source: i, sink: i}`. It is made from a random path through every cell of the lattice (a plain snake, shuffled
  by "backbite" moves), with the holes trimmed off the path's two ends, so what is left always has one stroke
  through all of it from source to sink; both of those lie on the lattice's edge, where a live line can reach
  them. The same seed always gives the same board.
  """
  @spec generate(pos_integer(), pos_integer(), non_neg_integer(), {integer(), integer(), integer()}) :: map()
  def generate(cols, rows, holes, seed) when cols >= 2 and rows >= 2 do
    holes = holes |> max(0) |> min(div(cols * rows, 4))
    rng = :rand.seed_s(:exsss, seed)
    attempt(cols, rows, holes, rng, 400)
  end

  defp attempt(cols, rows, _holes, _rng, 0) do
    path = snake(cols, rows)
    %{holes: [], source: hd(path), sink: List.last(path)}
  end

  defp attempt(cols, rows, holes, rng, tries) do
    {path, rng} = shuffle(snake(cols, rows), cols, rows, rng, cols * rows * 12)
    {cut, rng} = :rand.uniform_s(holes + 1, rng)
    cut_a = cut - 1
    trimmed = path |> Enum.drop(cut_a) |> Enum.take(length(path) - holes)
    source = hd(trimmed)
    sink = List.last(trimmed)

    if source != sink and on_edge?(source, cols, rows) and on_edge?(sink, cols, rows) do
      %{holes: Enum.sort(path -- trimmed), source: source, sink: sink}
    else
      attempt(cols, rows, holes, rng, tries - 1)
    end
  end

  defp snake(cols, rows) do
    Enum.flat_map(0..(rows - 1), fn r ->
      row = Enum.map(0..(cols - 1), &(r * cols + &1))
      if rem(r, 2) == 0, do: row, else: Enum.reverse(row)
    end)
  end

  defp shuffle(path, _cols, _rows, rng, 0), do: {path, rng}

  defp shuffle(path, cols, rows, rng, n) do
    {flip, rng} = :rand.uniform_s(rng)
    path = if flip < 0.5, do: Enum.reverse(path), else: path
    [last, prev | _] = Enum.reverse(path)
    opts = neighbours(last, cols, rows) -- [prev]

    case opts do
      [] ->
        shuffle(path, cols, rows, rng, n - 1)

      _ ->
        {k, rng} = :rand.uniform_s(length(opts), rng)
        to = Enum.at(opts, k - 1)
        at = Enum.find_index(path, &(&1 == to))
        {head, tail} = Enum.split(path, at + 1)
        shuffle(head ++ Enum.reverse(tail), cols, rows, rng, n - 1)
    end
  end

  @doc false
  def neighbours(i, cols, rows) do
    {c, r} = {rem(i, cols), div(i, cols)}

    [{c > 0, i - 1}, {c < cols - 1, i + 1}, {r > 0, i - cols}, {r < rows - 1, i + cols}]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp on_edge?(i, cols, rows) do
    {c, r} = {rem(i, cols), div(i, cols)}
    c == 0 or r == 0 or c == cols - 1 or r == rows - 1
  end
end
