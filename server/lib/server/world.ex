defmodule Server.World do
  @moduledoc """
  A shared world as a SUPERVISED PROCESS — now ONE process per `world_id` (multi-world). Each holds
  the live transforms of the players currently in *that* world and fans updates out on that world's
  own PubSub topic, so presence and motion are scoped per world: players in the Vale never see players
  in the Riverbank.

  Processes are started on demand (`ensure_started/1`) under a `DynamicSupervisor` and addressed
  through a `Registry` keyed by `world_id`. State is transient/in-memory — a crash restarts the world
  empty and its players re-sync on the next ~20 Hz tick (no player is harmed).

  Flow (per world), since SC-3 (docs/scaling-design.md):

      PlayerChannel handle_in("state") --cast--> World(world_id)  (sanitizes, stores latest, marks dirty)
      World(world_id), every 50 ms --Endpoint.broadcast "states" on "world:<id>"--> every socket

  The tick sends ONE bundle of every transform that changed since the last tick (`Server.WorldStates`
  is its compact format). `Endpoint.broadcast` on the channel topic uses Phoenix's "fastlane": the
  message is serialized to JSON once and that same frame goes straight to every player's socket,
  without passing through each player's channel process. So a tick costs one encode however many
  players there are, where it used to be one encode per recipient per movement. Each client skips its
  own entry. The ambient pals ride the same tick (every other one, 10 Hz), sent the same way.

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

  # The world's tick (SC-3): every 50 ms (20 Hz, the client's send rate) flush the bundle of changed
  # transforms; every other tick (10 Hz) also advance the ambient-pal sim and send it. The client eases
  # both streams into 60 fps.
  @tick_ms 50
  @ambient_every 2
  @ambient_dt 0.1

  # --- client API ---

  def start_link({world_id, ward_defs, ambient_core}) when is_binary(world_id) do
    GenServer.start_link(__MODULE__, {world_id, ward_defs, ambient_core}, name: via(world_id))
  end

  @doc """
  Start the process for `world_id` if it isn't running yet; returns `world_id`. `ward_defs` (the
  spec's `ruin.wards`, or `[]`) seed the shared Ruin ward state and `ambient_core` (the spec's whole
  `core` map, or `%{}`) seeds the ambient-pal sim — its pals AND the geometry they avoid. Only the FIRST
  starter's defs take; later joiners re-affirm the same server-canonical spec, so passing them every
  join is safe.
  """
  @spec ensure_started(String.t(), [map()], map()) :: String.t()
  def ensure_started(world_id, ward_defs \\ [], ambient_core \\ %{}) when is_binary(world_id) do
    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, {world_id, ward_defs, ambient_core}}) do
      {:ok, _pid} -> world_id
      {:error, {:already_started, _pid}} -> world_id
    end
  end

  @doc "Apply a player's Ruin ward INTENT (`%{\"kind\" => \"uncover\"|\"occupy\", \"ward\" => id, ...}`)."
  @spec apply_ward(String.t(), String.t(), map()) :: :ok
  def apply_ward(world_id, user_id, payload) do
    GenServer.cast(via(world_id), {:ward, user_id, payload})
  end

  @doc "The current shared ward state for `world_id` as `[%{id, found, open}]` (for the join snapshot)."
  @spec wards(String.t()) :: [map()]
  def wards(world_id), do: GenServer.call(via(world_id), :wards)

  @doc "The channel topic every player in `world_id` is joined to (where the tick's bundles go)."
  @spec channel_topic(String.t()) :: String.t()
  def channel_topic(world_id), do: "world:" <> world_id

  @doc "The PubSub topic this world broadcasts its other shared state on (the Ruin's wards)."
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

  @doc "The current ambient-pal transforms for `world_id` (`[%{id, p, l}]`), for the join snapshot."
  @spec ambient_snapshot(String.t()) :: [map()]
  def ambient_snapshot(world_id) do
    GenServer.call(via(world_id), :ambient)
  end

  # --- server callbacks ---

  @impl true
  def init({world_id, ward_defs, ambient_core}) do
    {:ok,
     %{
       world_id: world_id,
       transforms: %{},
       # Shared Ruin state: the pure ward logic + who is currently weighting each plate. occupants is a
       # MapSet of user_ids per ward, so two pairs can hold two plates and a leaver releases their own.
       ward_defs: ward_defs,
       wards: Server.RuinMechanisms.new(ward_defs),
       occupants: %{},
       # Shared ambient-pal sim: pure wander logic (incl. obstacle avoidance), ticked while at least one
       # player is here. `ticking` guards against scheduling more than one :tick timer at a time.
       ambient: Server.AmbientPals.new(ambient_core),
       # SC-3: who moved since the last tick (their entries go in the next bundle), and the tick count
       # (the ambient sim steps on every @ambient_every-th tick).
       dirty: MapSet.new(),
       tick_n: 0,
       ticking: false
     }}
  end

  @impl true
  def handle_cast({:update, user_id, transform}, state) do
    case Server.WorldStates.sanitize(transform) do
      nil ->
        # Nothing usable to relay, but the sender is still HERE (presence in this world is "has a
        # transform"; the Ruin resets when that empties), so note them without sending anything.
        {:noreply, maybe_start_ticking(%{state | transforms: Map.put_new(state.transforms, user_id, %{})})}

      clean ->
        state = %{state | transforms: Map.put(state.transforms, user_id, clean), dirty: MapSet.put(state.dirty, user_id)}
        {:noreply, maybe_start_ticking(state)}
    end
  end

  def handle_cast({:forget, user_id}, state) do
    transforms = Map.delete(state.transforms, user_id)
    state = %{state | dirty: MapSet.delete(state.dirty, user_id)}

    # Drop this player's weight from every plate (a disconnect mid-puzzle releases what they held).
    occupants = for {key, set} <- state.occupants, into: %{}, do: {key, MapSet.delete(set, user_id)}

    wards =
      Enum.reduce(occupants, state.wards, fn {{id, plate}, set}, w ->
        Server.RuinMechanisms.set_occupancy(w, id, plate, MapSet.size(set) > 0)
      end)

    state = %{state | transforms: transforms, occupants: occupants, wards: wards}

    # The room emptied: reset the puzzle so the next group finds it fresh (the shared echo of the
    # solo "resets each visit" feel).
    state =
      if map_size(transforms) == 0 do
        %{state | wards: Server.RuinMechanisms.new(state.ward_defs), occupants: %{}}
      else
        state
      end

    broadcast_wards(state)
    {:noreply, state}
  end

  def handle_cast({:ward, user_id, payload}, state) do
    state = apply_ward_intent(state, user_id, payload)
    broadcast_wards(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.transforms, state}

  def handle_call(:wards, _from, state), do: {:reply, Server.RuinMechanisms.to_list(state.wards), state}

  def handle_call(:ambient, _from, state), do: {:reply, Server.AmbientPals.to_list(state.ambient), state}

  # The world's tick: send the bundle of whoever moved, and (every other tick) advance the ambient-pal
  # sim and send that, but only while someone is here to see it. When the world empties, stop the loop
  # (the next arrival restarts it); idle worlds cost nothing.
  @impl true
  def handle_info(:tick, state) do
    if map_size(state.transforms) == 0 do
      {:noreply, %{state | ticking: false, dirty: MapSet.new()}}
    else
      topic = channel_topic(state.world_id)

      if MapSet.size(state.dirty) > 0 do
        moved = Map.take(state.transforms, MapSet.to_list(state.dirty))
        Server.Endpoint.broadcast(topic, "states", Server.WorldStates.bundle(moved))
      end

      n = state.tick_n + 1

      ambient =
        if rem(n, @ambient_every) == 0 and Server.AmbientPals.any?(state.ambient) do
          a = Server.AmbientPals.tick(state.ambient, @ambient_dt)
          Server.Endpoint.broadcast(topic, "ambient_state", %{pals: Server.AmbientPals.to_list(a)})
          a
        else
          state.ambient
        end

      Process.send_after(self(), :tick, @tick_ms)
      {:noreply, %{state | ambient: ambient, dirty: MapSet.new(), tick_n: n}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- internals ---

  # Kick off the tick when someone's here. No-op if it's already running, so it's called on every
  # transform.
  defp maybe_start_ticking(%{ticking: true} = state), do: state

  defp maybe_start_ticking(state) do
    Process.send_after(self(), :tick, @tick_ms)
    %{state | ticking: true}
  end

  # A player's companion uncovered a plate (its search nosed it out).
  defp apply_ward_intent(state, _user_id, %{"kind" => "uncover", "ward" => id}) do
    %{state | wards: Server.RuinMechanisms.uncover(state.wards, to_string(id))}
  end

  # A player's companion (or a wedge) stepped onto / off a plate. occupants is the live set of user_ids
  # per {ward, plate} — "plate" selects which plate of a PAIRED ward (the Paired Hall) and is "" for a
  # single ward. The plate bears weight while any companion stands on it; a paired door opens only when
  # all its plates do at once.
  defp apply_ward_intent(state, user_id, %{"kind" => "occupy", "ward" => id} = payload) do
    id = to_string(id)
    plate = to_string(Map.get(payload, "plate", ""))
    on = Map.get(payload, "on", false) == true
    key = {id, plate}
    set0 = Map.get(state.occupants, key, MapSet.new())
    set = if on, do: MapSet.put(set0, user_id), else: MapSet.delete(set0, user_id)

    %{
      state
      | occupants: Map.put(state.occupants, key, set),
        wards: Server.RuinMechanisms.set_occupancy(state.wards, id, plate, MapSet.size(set) > 0)
    }
  end

  defp apply_ward_intent(state, _user_id, _payload), do: state

  # Fan the shared ward state out to every channel in this world (which push "ward_state" to clients).
  # No-op in worlds without a Ruin, so the common case costs nothing.
  defp broadcast_wards(%{ward_defs: []}), do: :ok

  defp broadcast_wards(state) do
    Phoenix.PubSub.broadcast(
      Server.PubSub,
      state_topic(state.world_id),
      {:world_wards, Server.RuinMechanisms.to_list(state.wards)}
    )
  end

  defp via(world_id), do: {:via, Registry, {@registry, world_id}}
end
