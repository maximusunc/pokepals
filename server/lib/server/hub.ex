defmodule Server.Hub do
  @moduledoc """
  A monotonic id counter — nothing more. Each connection gets a fresh integer id, which the client
  protocol uses to identify peers and which `Server.Presence` uses as its roster key.

  The roster itself now lives in `Server.Presence` (a CRDT); the Hub's only remaining job is handing
  out unique ids. Ids are never reused within a server lifetime, which keeps "who is who" unambiguous
  in logs and on the wire.
  """
  use GenServer

  # --- client API ---

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Hand out the next unique connection id."
  @spec next_id() :: pos_integer()
  def next_id, do: GenServer.call(__MODULE__, :next_id)

  # --- server callbacks ---

  @impl true
  def init(_), do: {:ok, 1}

  @impl true
  def handle_call(:next_id, _from, id), do: {:reply, id, id + 1}
end
