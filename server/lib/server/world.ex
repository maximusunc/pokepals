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

  Only changes are sent (SC-4): a player is marked dirty only when their cleaned transform differs
  from the stored one, ignoring the load-test stamp `t`. Clients send while they move and once a
  second otherwise (a keepalive); a keepalive that changes nothing is dropped, but its sender is still
  stored, so still present.

  ## Interest cells (SC-4), opt-in per world

  A world whose spec has a crowd block (`core.crowd`, e.g. `{"cell": 480, "full": 40, "lite": 80}`) is
  cut into `cell` x `cell` px squares (`Server.Interest`). The world process reads the block from the
  `core` map it's started with (`ensure_started/3`'s third argument, the same one the ambient pals read).
  In such a world a client hears only the players in the 3 x 3 cells around its own:

    * Each tick, every mover is placed in the cell of its player position, and ONE bundle per occupied
      cell (a cell someone stands in) goes out on that cell's PubSub topic (`Interest.topic/2`), holding
      the movers in its 3 x 3 neighbourhood. The bundle is a `%Phoenix.Socket.Broadcast{}` on the
      world's CHANNEL topic, so it reaches a socket through the same fastlane as before (encoded once per
      cell) and the client sees an ordinary `"states"` frame. Nothing goes out on the world-wide topic.
    * Each channel follows exactly one cell topic, its own player's (`Server.WorldChannel`), and when
      that cell changes it is pushed one snapshot of the players in the cells that just came into view.
  Ambient pals, wards, flares, howls and the presence roster (join / identity / leave) stay world-wide.

  Edge cases, decided:
    * A mover crossing a cell border: its entry for that tick goes to the old cell's neighbourhood AND
      the new one's, so watchers it's leaving see the position it left to (now more than a cell away
      from them, so their client stops drawing it) and the ones it's reaching see it arrive. From the
      next tick only the new neighbourhood hears it.
    * A watcher who walks away from someone standing still hears nothing about them: its own client
      knows it moved and hides peers whose last position is more than a cell away. Walking back brings
      them in again through the newly-visible snapshot.
    * A player who hasn't sent a state yet has no cell and is in no bundle. Its channel subscribes to
      the cell of its spawn (or resume) point on join and gets that neighbourhood as the join
      snapshot; with neither, it receives nothing until its first state names its cell, then the full
      neighbourhood as a snapshot.
    * A packet with no player position (`p`) leaves the player in the cell it was in (or none).
    * `forget` (leaving) drops the player from its cell. An emptied cell leaves the index, so it's no
      longer occupied and costs nothing; the leaver's peers learn of the leave from presence.
    * A world restart: the process starts empty with the same spec. Channels keep their cell
      subscriptions (those live in PubSub, not here). Every client re-sends within a second (the
      keepalive), which is a change against an empty store, so everyone is placed and re-sent to their
      neighbourhood again.
    * Snapshots drop the load-test stamp `t` (`WorldStates.snapshot_bundle/1`).

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

  @doc """
  The latest transforms of the players standing in `cells` of a crowd world (SC-4), by the cells the
  world last placed them in (`%{user_id => transform}`). `%{}` in a world without interest cells, or if
  the world process is briefly unavailable (a restart): the next ticks fill in.
  """
  @spec snapshot_cells(String.t(), [Server.Interest.cell()]) :: %{optional(String.t()) => map()}
  def snapshot_cells(world_id, cells) do
    GenServer.call(via(world_id), {:snapshot_cells, cells})
  catch
    :exit, _ -> %{}
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
       # SC-4: interest cells, only in a world whose spec has a crowd block (`core.crowd.cell`); nil
       # everywhere else, and then nothing below about cells is used. `cells` is each player's cell as of
       # the last tick, `members` the reverse index (only cells someone stands in).
       interest: Server.Interest.config(ambient_core),
       cells: %{},
       members: %{},
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
        if same_transform?(Map.get(state.transforms, user_id), clean) do
          # Only changes are sent (SC-4): a packet that says nothing new (a client's 1 Hz keepalive
          # while standing still) isn't relayed. The sender is already stored, so still counts as here.
          {:noreply, maybe_start_ticking(state)}
        else
          state = %{state | transforms: Map.put(state.transforms, user_id, clean), dirty: MapSet.put(state.dirty, user_id)}
          {:noreply, maybe_start_ticking(state)}
        end
    end
  end

  def handle_cast({:forget, user_id}, state) do
    transforms = Map.delete(state.transforms, user_id)
    state = %{state | dirty: MapSet.delete(state.dirty, user_id)} |> leave_cell(user_id)

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

  def handle_call({:snapshot_cells, cells}, _from, state) do
    ids = Enum.flat_map(cells, fn c -> state.members |> Map.get(c, MapSet.new()) |> MapSet.to_list() end)
    {:reply, Map.take(state.transforms, ids), state}
  end

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
      state = flush_states(state, topic)

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

  # Whether a cleaned transform says the same as the stored one. The load-test send stamp `t` changes on
  # every packet, so it's left out of the comparison: an unchanged pose with a new `t` is not a change
  # (and isn't stored either); a changed pose is stored with its own, latest `t`.
  defp same_transform?(nil, _clean), do: false
  defp same_transform?(old, clean), do: Map.delete(old, "t") == Map.delete(clean, "t")

  # Send this tick's moved transforms. A world without interest cells sends one bundle to everyone (SC-3).
  defp flush_states(%{interest: nil} = state, topic) do
    if MapSet.size(state.dirty) > 0 do
      moved = Map.take(state.transforms, MapSet.to_list(state.dirty))
      Server.Endpoint.broadcast(topic, "states", Server.WorldStates.bundle(moved))
    end

    state
  end

  # A crowd world (SC-4): move each mover to its new cell, then send ONE bundle per occupied cell, on that
  # cell's topic, of the movers in its 3 x 3 neighbourhood. A mover that changed cell this tick goes to its
  # old neighbourhood too, so watchers there see where it went. Each bundle is a channel Broadcast on the
  # world's channel topic, so the fastlane encodes it once for every socket subscribed to that cell.
  defp flush_states(%{interest: %{cell: size}} = state, topic) do
    if MapSet.size(state.dirty) == 0 do
      state
    else
      {moved, state} =
        Enum.reduce(state.dirty, {[], state}, fn uid, {acc, st} ->
          case Map.fetch(st.transforms, uid) do
            {:ok, t} ->
              old = Map.get(st.cells, uid)

              new =
                case Map.get(t, "p") do
                  [_, _] = p -> Server.Interest.cell_of(p, size)
                  _ -> old
                end

              st = move_cell(st, uid, old, new)
              route = Enum.uniq(for c <- [new, old], c != nil, do: c)
              {[{encoded_entry(uid, t), route} | acc], st}

            :error ->
              {acc, st}
          end
        end)

      for {cell, entries} <- Server.Interest.group(moved, state.members) do
        Phoenix.PubSub.broadcast(Server.PubSub, Server.Interest.topic(state.world_id, cell), %Phoenix.Socket.Broadcast{
          topic: topic,
          event: "states",
          payload: %{s: entries}
        })
      end

      state
    end
  end

  # One mover's entry, JSON-encoded ONCE for this tick. A mover sits in up to nine (eighteen, crossing a
  # border) cell bundles, and encoding the bundles from plain lists cost ~9x the encoding; as a
  # `Jason.Fragment` the fastlane's encoder copies the bytes in as they are. The JSON on the wire is the
  # same. (The fragment holds a closure, so a bundle crossing to another node needs the same code there.)
  defp encoded_entry(uid, t) do
    Jason.Fragment.new(Jason.encode_to_iodata!(Server.WorldStates.entry(uid, t)))
  end

  defp move_cell(state, _uid, same, same), do: state

  defp move_cell(state, uid, old, new) do
    members = if old, do: drop_member(state.members, old, uid), else: state.members
    members = Map.update(members, new, MapSet.new([uid]), &MapSet.put(&1, uid))
    %{state | cells: Map.put(state.cells, uid, new), members: members}
  end

  defp leave_cell(state, uid) do
    case Map.pop(state.cells, uid) do
      {nil, _} -> state
      {cell, cells} -> %{state | cells: cells, members: drop_member(state.members, cell, uid)}
    end
  end

  # An emptied cell leaves the index, so it's no longer "occupied" and gets no bundles.
  defp drop_member(members, cell, uid) do
    case Map.fetch(members, cell) do
      {:ok, set} ->
        set = MapSet.delete(set, uid)
        if MapSet.size(set) == 0, do: Map.delete(members, cell), else: Map.put(members, cell, set)

      :error ->
        members
    end
  end

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
