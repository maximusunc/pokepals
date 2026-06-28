defmodule Server.RuinMechanisms do
  @moduledoc """
  The Ruin's pair-operated mechanisms as PURE LOGIC, SERVER-SIDE — the authority for shared worlds.

  This is the Elixir port of the client's reference rules (was `scripts/world/ruin_mechanisms.gd`):
  a hidden plate the companion's search uncovers, weight on an uncovered plate raising a linked slab,
  a latched Threshold slab staying open once raised, and the uncover/settle ORDER never mattering
  (opening is recomputed from found && occupied). State in, state out — no processes, no IO — so it's
  unit-testable and a `Server.World` GenServer can simply hold it and broadcast `to_list/1` on change.

  State is `%{ward_id => %{found, occupied, open, latch}}`. The client now owns only PRESENTATION and
  DETECTION: it reports abstract intents (`uncover`, `occupy on/off`) for its own companion and renders
  whatever ward state the server broadcasts back — so two players' companions can work the same wards
  and everyone converges on one truth. The non-latching ward (open only while weighted) is the seam the
  later Paired Hall's "slips the moment it leaves" beat will use.
  """

  @type ward :: %{found: boolean, occupied: boolean, open: boolean, latch: boolean}
  @type t :: %{optional(String.t()) => ward}

  @doc "Build fresh ward state from the spec's `ruin.wards` defs (`[%{\"id\" => , \"latch\" => }]`)."
  @spec new([map()]) :: t
  def new(ward_defs) when is_list(ward_defs) do
    for wd <- ward_defs, into: %{} do
      id = to_string(Map.get(wd, "id", "ward"))
      {id, %{found: false, occupied: false, open: false, latch: Map.get(wd, "latch", true) == true}}
    end
  end

  def new(_), do: %{}

  @doc "The companion's search uncovered this plate. Idempotent; opening is recomputed (so settle-first works)."
  @spec uncover(t, String.t()) :: t
  def uncover(state, id), do: update(state, id, fn w -> %{w | found: true} end)

  @doc "Whether weight rests on this plate now. Opening requires the plate to be found as well."
  @spec set_occupied(t, String.t(), boolean) :: t
  def set_occupied(state, id, occupied), do: update(state, id, fn w -> %{w | occupied: occupied} end)

  defp update(state, id, fun) do
    case Map.fetch(state, id) do
      {:ok, w} -> Map.put(state, id, recompute(fun.(w)))
      :error -> state
    end
  end

  # open = found && occupied, honouring the latch (sticky once open). Order-independent.
  defp recompute(%{found: f, occupied: o, latch: latch} = w) do
    cond do
      f and o -> %{w | open: true}
      not latch -> %{w | open: false}
      true -> w
    end
  end

  @spec found?(t, String.t()) :: boolean
  def found?(state, id), do: match?(%{found: true}, Map.get(state, id))

  @spec open?(t, String.t()) :: boolean
  def open?(state, id), do: match?(%{open: true}, Map.get(state, id))

  @doc "The wire shape the client renders: `[%{id, found, open}]`."
  @spec to_list(t) :: [map()]
  def to_list(state) do
    for {id, w} <- state, do: %{id: id, found: w.found, open: w.open}
  end
end
