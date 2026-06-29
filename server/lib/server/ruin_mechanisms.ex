defmodule Server.RuinMechanisms do
  @moduledoc """
  The Ruin's pair-operated mechanisms as PURE LOGIC, SERVER-SIDE — the authority for shared worlds.

  Two ward shapes:

    * SINGLE — `%{found, occupied, open, latch}`. A plate the companion's search uncovers (`found`)
      and weights (`occupied`); the linked slab opens when both hold, sticky if `latch`. Order never
      matters. Powers the Threshold (buried plate), the Warren (the true gap), and the Cistern (the
      kindle stands in for `found`, the carry-delivery for `occupied`).

    * PAIRED — `%{paired: true, plates: %{"a" => bool, "b" => bool}, open, latch}`. The PAIRED HALL:
      a door that opens only when EVERY plate bears weight AT ONCE — which is why it takes two pairs
      (one companion to each plate), or, alone, a wedge holding one plate while your companion holds
      the other. This is the whole reason shared state went authoritative: only the server sees both
      plates' occupancy at the same instant. A ward def becomes paired by carrying a `"plates"` list.

  State in, state out — no processes, no IO — so it's unit-testable and `Server.World` just holds it
  and broadcasts `to_list/1` on change. The client owns presentation/detection and reports abstract
  intents (`uncover`, `occupy {plate, on}`); the server combines them and echoes one truth back.
  """

  @type single :: %{found: boolean, occupied: boolean, open: boolean, latch: boolean}
  @type paired :: %{paired: true, plates: %{optional(String.t()) => boolean}, open: boolean, latch: boolean}
  @type t :: %{optional(String.t()) => single | paired}

  @doc "Build fresh ward state from the spec's `ruin.wards` defs. A def with a `\"plates\"` list is paired."
  @spec new([map()]) :: t
  def new(ward_defs) when is_list(ward_defs) do
    for wd <- ward_defs, into: %{} do
      id = to_string(Map.get(wd, "id", "ward"))
      latch = Map.get(wd, "latch", true) == true

      case Map.get(wd, "plates") do
        plates when is_list(plates) and plates != [] ->
          {id, %{paired: true, plates: Map.new(plates, &{to_string(&1), false}), open: false, latch: latch}}

        _ ->
          {id, %{found: false, occupied: false, open: false, latch: latch}}
      end
    end
  end

  def new(_), do: %{}

  @doc "A single ward's plate was uncovered by the search. Idempotent. Paired wards have no `found`."
  @spec uncover(t, String.t()) :: t
  def uncover(state, id) do
    case Map.fetch(state, id) do
      {:ok, %{paired: true}} -> state
      {:ok, w} -> Map.put(state, id, recompute(%{w | found: true}))
      :error -> state
    end
  end

  @doc """
  Set whether weight rests on a plate now. `plate` selects which plate of a PAIRED ward; it is ignored
  for a SINGLE ward (pass `""`). A single ward opens on found && occupied; a paired ward opens only when
  ALL its plates bear weight at once. Both honour `latch` (sticky once open).
  """
  @spec set_occupancy(t, String.t(), String.t(), boolean) :: t
  def set_occupancy(state, id, plate, occupied) do
    case Map.fetch(state, id) do
      {:ok, %{paired: true} = w} ->
        Map.put(state, id, recompute_paired(%{w | plates: Map.put(w.plates, to_string(plate), occupied)}))

      {:ok, w} ->
        Map.put(state, id, recompute(%{w | occupied: occupied}))

      :error ->
        state
    end
  end

  @doc "Convenience for SINGLE wards (and the tests): occupancy with no plate."
  @spec set_occupied(t, String.t(), boolean) :: t
  def set_occupied(state, id, occupied), do: set_occupancy(state, id, "", occupied)

  # SINGLE: open = found && occupied, honouring the latch (sticky once open). Order-independent.
  defp recompute(%{found: f, occupied: o, latch: latch} = w) do
    cond do
      f and o -> %{w | open: true}
      not latch -> %{w | open: false}
      true -> w
    end
  end

  # PAIRED: open only while EVERY plate bears weight at once; latch keeps it open once all have.
  defp recompute_paired(%{plates: plates, latch: latch} = w) do
    cond do
      Enum.all?(Map.values(plates)) -> %{w | open: true}
      not latch -> %{w | open: false}
      true -> w
    end
  end

  @spec found?(t, String.t()) :: boolean
  def found?(state, id), do: match?(%{found: true}, Map.get(state, id))

  @spec open?(t, String.t()) :: boolean
  def open?(state, id), do: match?(%{open: true}, Map.get(state, id))

  @doc "The wire shape the client renders. Single: `%{id, found, open}`. Paired: `%{id, open, plates}`."
  @spec to_list(t) :: [map()]
  def to_list(state) do
    for {id, w} <- state do
      case w do
        %{paired: true} -> %{id: id, open: w.open, plates: w.plates}
        _ -> %{id: id, found: w.found, open: w.open}
      end
    end
  end
end
