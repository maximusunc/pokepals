defmodule Server.World.Context do
  @moduledoc """
  The bound world context handed to creator code. It carries the `world_id` the caller is scoped to —
  and NOTHING the caller can use to reach another world. The runtime constructs it (from the world
  process / channel session); creator code receives an already-bound ctx and cannot rebind or forge
  one (in a real sandboxed-script host, `new/1` is not exposed to creator scripts).

  This indirection is the whole isolation story: every `Server.World.Sandbox` call takes a ctx and
  reads `world_id` from it — never from caller-supplied arguments — so a cross-world query is
  unconstructable (§4 rule 1, §10 invariant).
  """
  @enforce_keys [:world_id]
  defstruct [:world_id]

  @type t :: %__MODULE__{world_id: Ecto.UUID.t()}

  @doc "Bind a context to a world. Called by the runtime, not by creator code."
  @spec new(Ecto.UUID.t()) :: t()
  def new(world_id) when is_binary(world_id), do: %__MODULE__{world_id: world_id}
end
