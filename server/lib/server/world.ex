defmodule Server.World do
  @moduledoc """
  The shared world as a SUPERVISED PROCESS — the live, authoritative owner of every connected
  player's latest transform (their + their companion's position/facing). This is the seam the rest of
  Rung 4+ builds on: instead of channels blindly relaying transforms to each other, one process holds
  "where is everyone right now" in memory, so a late-joiner can be shown everyone's current positions
  the instant they arrive (the `snapshot/1`), and so future server-side world logic has a single
  place to live.

  Flow (the ~20 Hz hot path):

      PlayerChannel handle_in("state") --cast--> World (stores latest in memory)
      World --PubSub.broadcast on state_topic--> every channel --push("state")--> clients

  State is intentionally TRANSIENT and in-memory. If this process crashes, the supervisor restarts it
  empty and players re-sync on their next ~20 Hz tick — acceptable by design, because no player is
  harmed (positions aren't money or items). There is exactly ONE world right now (a single named
  instance); it is not yet per-world or distributed.

  ── DEFERRED SEAMS (do NOT build until the need is real) ──────────────────────────────────────────
    * WRITE-BEHIND PERSISTENCE: the spec flushes transient state to Postgres every ~30 s (via Oban).
      There is nothing here worth persisting yet — the canonical save (companion + appearance) already
      goes through `Server.Saves` on its own frame, and positions are ephemeral. When some transient
      state genuinely must survive a restart, add the periodic flush + Oban THEN. (No Oban dep now.)
    * MULTI-WORLD: today this is one global named process. Becoming one process per `world_id` (a
      `DynamicSupervisor` + a registry) is a later step — and a cluster-aware registry (Horde) is a
      SCALE concern beyond that. Keep the single instance until a second world actually exists.
    * CROSS-NODE: Phoenix.PubSub already spans a cluster; nothing Redis is needed here, and won't be
      unless/until the nodes can't cluster over distributed Erlang. Not now.
  ──────────────────────────────────────────────────────────────────────────────────────────────────
  """
  use GenServer

  @state_topic "world:state"

  # --- client API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @doc "The PubSub topic the world broadcasts live transforms on. Channels subscribe to it."
  @spec state_topic() :: String.t()
  def state_topic, do: @state_topic

  @doc "Record a player's latest transform and fan it out to the world. Fire-and-forget."
  @spec update_transform(GenServer.server(), String.t(), map()) :: :ok
  def update_transform(world \\ __MODULE__, user_id, transform) do
    GenServer.cast(world, {:update, user_id, transform})
  end

  @doc "Drop a player's transform when they leave, so it isn't shown to future joiners."
  @spec forget(GenServer.server(), String.t()) :: :ok
  def forget(world \\ __MODULE__, user_id) do
    GenServer.cast(world, {:forget, user_id})
  end

  @doc "Everyone's latest transform right now, as `%{user_id => transform}`. For late-joiner sync."
  @spec snapshot(GenServer.server()) :: %{optional(String.t()) => map()}
  def snapshot(world \\ __MODULE__) do
    GenServer.call(world, :snapshot)
  end

  # --- server callbacks ---

  @impl true
  def init(:ok), do: {:ok, %{transforms: %{}}}

  @impl true
  def handle_cast({:update, user_id, transform}, state) do
    state = put_in(state.transforms[user_id], transform)
    # Broadcast to all subscribed channels (including the sender's — its channel drops its own echo).
    Phoenix.PubSub.broadcast(Server.PubSub, @state_topic, {:world_state, user_id, transform})
    {:noreply, state}
  end

  def handle_cast({:forget, user_id}, state) do
    {:noreply, update_in(state.transforms, &Map.delete(&1, user_id))}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state.transforms, state}
  end
end
