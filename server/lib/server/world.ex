defmodule Server.World do
  @moduledoc """
  A shared world as a SUPERVISED PROCESS — now ONE process per `world_id` (multi-world). Each holds
  the live transforms of the players currently in *that* world and fans updates out on that world's
  own PubSub topic, so presence and motion are scoped per world: players in the Vale never see players
  in the Riverbank.

  Processes are started on demand (`ensure_started/1`) under a `DynamicSupervisor` and addressed
  through a `Registry` keyed by `world_id`. State is transient/in-memory — a crash restarts the world
  empty and its players re-sync on the next ~20 Hz tick (no player is harmed).

  Flow (per world):

      PlayerChannel handle_in("state") --cast--> World(world_id)  (stores latest)
      World(world_id) --PubSub.broadcast on state_topic(world_id)--> that world's channels --push-->

  ── DEFERRED SEAMS (scale — NOT built; flagged):
    * WRITE-BEHIND PERSISTENCE of transient state (Oban) — nothing here is worth persisting yet.
    * CLUSTER-AWARE registry: today `Registry` + `DynamicSupervisor` are NODE-LOCAL, so a given
      `world_id` resolves to a process on THIS node only. Going multi-node means a cluster-aware
      registry (Horde) + libcluster so each `world_id` has one owner cluster-wide — that's the scale
      step, intentionally deferred. PubSub already spans a cluster if one exists.
  ──
  """
  use GenServer

  @registry Server.WorldRegistry
  @supervisor Server.WorldSupervisor

  # --- client API ---

  def start_link(world_id) when is_binary(world_id) do
    GenServer.start_link(__MODULE__, world_id, name: via(world_id))
  end

  @doc "Start the process for `world_id` if it isn't running yet; returns `world_id`."
  @spec ensure_started(String.t()) :: String.t()
  def ensure_started(world_id) when is_binary(world_id) do
    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, world_id}) do
      {:ok, _pid} -> world_id
      {:error, {:already_started, _pid}} -> world_id
    end
  end

  @doc "The PubSub topic this world broadcasts live transforms on."
  @spec state_topic(String.t()) :: String.t()
  def state_topic(world_id), do: "world:#{world_id}:state"

  @doc "Record a player's latest transform in `world_id` and fan it out. Fire-and-forget."
  @spec update_transform(String.t(), String.t(), map()) :: :ok
  def update_transform(world_id, user_id, transform) do
    GenServer.cast(via(world_id), {:update, user_id, transform})
  end

  @doc "Drop a player's transform from `world_id` when they leave."
  @spec forget(String.t(), String.t()) :: :ok
  def forget(world_id, user_id) do
    GenServer.cast(via(world_id), {:forget, user_id})
  end

  @doc "Everyone's latest transform in `world_id` right now (`%{user_id => transform}`)."
  @spec snapshot(String.t()) :: %{optional(String.t()) => map()}
  def snapshot(world_id) do
    GenServer.call(via(world_id), :snapshot)
  end

  # --- server callbacks ---

  @impl true
  def init(world_id), do: {:ok, %{world_id: world_id, transforms: %{}}}

  @impl true
  def handle_cast({:update, user_id, transform}, state) do
    state = put_in(state.transforms[user_id], transform)
    Phoenix.PubSub.broadcast(Server.PubSub, state_topic(state.world_id), {:world_state, user_id, transform})
    {:noreply, state}
  end

  def handle_cast({:forget, user_id}, state) do
    {:noreply, update_in(state.transforms, &Map.delete(&1, user_id))}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.transforms, state}

  # --- internals ---

  defp via(world_id), do: {:via, Registry, {@registry, world_id}}
end
