defmodule Server.Hub do
  @moduledoc """
  The only shared state in the relay: monotonic id assignment and the roster of currently
  connected clients (`id => identity`). This is the server-authoritative identity/routing root —
  every relayed frame is stamped with the id the Hub handed out, so a client can't impersonate
  another.

  Identity is the latest one a client sent (or an empty map until it sends one); it's kept so a
  late joiner can be told who's already here in its `welcome`. In-memory only — server-canonical
  persistence (Postgres) is a later Rung-4 step.
  """
  use GenServer

  # --- client API ---

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Register a new connection. Returns `{assigned_id, peers_already_here}`."
  @spec join() :: {pos_integer(), [map()]}
  def join, do: GenServer.call(__MODULE__, :join)

  @doc "Store the latest identity a connection sent (ignored if it has already left)."
  def put_identity(id, identity), do: GenServer.cast(__MODULE__, {:put_identity, id, identity})

  @doc "Remove a connection from the roster."
  def drop(id), do: GenServer.cast(__MODULE__, {:drop, id})

  # --- server callbacks ---

  @impl true
  def init(_), do: {:ok, %{next_id: 1, roster: %{}}}

  @impl true
  def handle_call(:join, _from, %{next_id: id, roster: roster} = state) do
    peers = Enum.map(roster, fn {pid, identity} -> %{id: pid, identity: identity} end)
    {:reply, {id, peers}, %{state | next_id: id + 1, roster: Map.put(roster, id, %{})}}
  end

  @impl true
  def handle_cast({:put_identity, id, identity}, %{roster: roster} = state) do
    # Only update a member that's still present, so a late cast can't resurrect a dropped peer.
    roster = if Map.has_key?(roster, id), do: Map.put(roster, id, identity), else: roster
    {:noreply, %{state | roster: roster}}
  end

  def handle_cast({:drop, id}, %{roster: roster} = state) do
    {:noreply, %{state | roster: Map.delete(roster, id)}}
  end
end
