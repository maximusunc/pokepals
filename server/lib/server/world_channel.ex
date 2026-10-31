defmodule Server.WorldChannel do
  @moduledoc """
  One shared world, as a Phoenix Channel on the topic `"world:" <> world_id`. Multi-world: each world
  has its own topic, so Presence (the roster) and the live-transform fan-out are scoped per world —
  players in different worlds don't see each other. A client joins the channel for the world it is in
  and re-joins (leave + join) when it travels.

  On join we resolve the world's definition (catalog), ensure its live `Server.World` process exists,
  and on `:after_join`:

    * deliver the world SPEC — `world_spec` with the catalog's spec + content `etag`, UNLESS the client
      passed a matching `known_etag` (then `world_spec_unchanged`, so cached specs aren't re-sent),
    * `Presence.track` ourselves on this world's topic and push `welcome` (this world's roster),
    * push `load` (our canonical companion + appearance — a per-USER concern, same in every world),
    * replay the world's transform `snapshot` so peers already moving appear at once.

  Thereafter: `identity` → Presence.update; `state` → cast to this world's `Server.World`; `flare` →
  relay a touched glow-plant to everyone else in the world; `save` → persist by user_id; `list_worlds` → a `world_list` page of the directory (the Vale's Gateway);
  presence diffs → join/identity/leave frames. The sender id is always
  server-stamped (the player's user_id); clients never send their own id.
  """
  use Phoenix.Channel
  require Logger
  alias Server.{Discoveries, Economy, Friends, HomePasses, Homes, HomeWorld, Presence, PresenceFrames, Profiles, Saves, Social, World, Worlds}

  # The currency the shop charges in. One place to name it so the join push and the buy handler agree.
  @shop_currency "coins"

  # What the riverbank salamander hunt pays out, keyed by how many of the ten were found. Fewer than
  # six earns nothing (absent keys default to 0). Server-authoritative: the client reports the count,
  # the server alone decides the reward, mints it, and ledgers it — UGC/world code never touches this.
  @hunt_rewards %{10 => 10, 9 => 7, 8 => 5, 7 => 2, 6 => 1}

  # What reaching the heart of the hedge maze pays out. Server-authoritative and honoured only in a
  # world whose spec carries the "reach_center" goal, so it can't be claimed from anywhere else.
  @maze_reward 10

  intercept ["presence_diff"]

  # A player's HOME WORLD (`"world:home:" <> owner_user_id`): not a catalog row but a spec built for its
  # owner (Server.HomeWorld). The owner may always enter; anyone else only while it's open, with no
  # block between them, as a friend or with a one-off pass from an accepted invite (Server.Homes). A
  # pass is used up on the way in. Everything after the join is the same as any world.
  @impl true
  def join("world:home:" <> owner_id, payload, socket) do
    user_id = socket.assigns.user_id

    if owner_id != "" and Homes.can_visit?(user_id, owner_id) do
      if user_id != owner_id and not Friends.friends?(user_id, owner_id), do: HomePasses.consume(owner_id, user_id)
      definition = HomeWorld.definition(owner_id, user_id)
      world_id = definition.world_id
      World.ensure_started(world_id, [], ambient_core(definition))
      send(self(), :after_join)

      {:ok,
       assign(socket, %{
         world_id: world_id,
         definition: definition,
         known_etag: Map.get(payload, "known_etag", ""),
         known: MapSet.new()
       })}
    else
      {:error, %{reason: "not_allowed"}}
    end
  end

  def join("world:" <> world_id, payload, socket) when world_id != "" do
    case Worlds.get(world_id) do
      nil ->
        Logger.warning("rejected join for unknown world #{inspect(world_id)} — is the catalog seeded? (mix run priv/repo/seeds.exs)")
        {:error, %{reason: "unknown_world"}}

      definition ->
        World.ensure_started(world_id, ward_defs(definition), ambient_core(definition))
        known_etag = Map.get(payload, "known_etag", "")
        send(self(), :after_join)

        {:ok,
         assign(socket, %{
           world_id: world_id,
           definition: definition,
           known_etag: known_etag,
           known: MapSet.new()
         })}
    end
  end

  def join(_topic, _payload, _socket), do: {:error, %{reason: "bad_topic"}}

  @impl true
  def handle_info(:after_join, socket) do
    %{world_id: world_id, user_id: user_id, definition: definition, known_etag: known_etag} =
      socket.assigns

    # Deliver the spec (or confirm the client's cache is current). The cache validator is a content
    # ETAG (Worlds.etag/1), so any back-end edit to a world invalidates the client's cache on its
    # own — there is no version to remember to bump and no new client build to ship for a world edit.
    etag = Worlds.etag(definition)

    # The world secrets we've found — a per-USER concern, like the save. Sent BEFORE the spec, so a world
    # built straight from it already knows to leave a found secret out (the maze's seed, once taken).
    push(socket, "discoveries", %{ids: Discoveries.list(user_id)})

    if etag == known_etag do
      push(socket, "world_spec_unchanged", %{world_id: world_id, version: definition.version, etag: etag})
    else
      push(socket, "world_spec", Worlds.client_view(definition))
    end

    topic = "world:" <> world_id
    Phoenix.PubSub.subscribe(Server.PubSub, World.state_topic(world_id))
    # Our own social topic (friend requests, invites, list changes, being sent home) and the "online"
    # roster friends read our status from. Both follow us from world to world.
    Phoenix.PubSub.subscribe(Server.PubSub, Friends.user_topic(user_id))
    Social.track_online(self(), user_id)
    profile = Profiles.ensure(user_id)
    socket = assign(socket, :name, profile.name)
    push(socket, "profile", %{id: user_id, name: profile.name, friend_code: profile.friend_code})
    push(socket, "friends", Social.snapshot(user_id))
    {:ok, _ref} = Presence.track(socket, user_id, %{identity: %{}})

    peers = PresenceFrames.peers(Presence.list(topic), user_id)
    known = MapSet.new(peers, & &1.id)
    push(socket, "welcome", %{id: user_id, peers: peers})

    save = Saves.load(user_id)
    push(socket, "load", %{companion: save.companion, appearance: save.appearance})

    # The economy snapshot — our wallet + the shop's color stock, each flagged owned. A per-USER
    # concern (same in every world); the bazaar's shop reads it, every other world just ignores it.
    push(socket, "economy", economy_snapshot(user_id))

    # Where everyone already here is right now, as one bundle in the same form as the live ticks.
    case Map.delete(World.snapshot(world_id), user_id) do
      peers when map_size(peers) == 0 -> :ok
      peers -> push(socket, "states", Server.WorldStates.bundle(peers))
    end

    # The ambient pals' current positions, so a late joiner sees them where they are right now rather
    # than snapping in from their home spots on the next tick. Empty (skipped) in worlds without pals.
    case World.ambient_snapshot(world_id) do
      [] -> :ok
      pals -> push(socket, "ambient_state", %{pals: pals})
    end

    # The shared Ruin ward state, so a late joiner sees a gate someone already opened (and the slab
    # already raised). Empty in worlds without a Ruin, so we skip the push there.
    case World.wards(world_id) do
      [] -> :ok
      wards -> push(socket, "ward_state", %{wards: wards})
    end

    {:noreply, assign(socket, :known, known)}
  end

  # (Live transforms and the ambient pals no longer pass through here: since SC-3 the world process
  # broadcasts one "states" / "ambient_state" bundle per tick straight to every socket. See Server.World.)

  # The shared Ruin ward state changed (someone's companion uncovered/weighted a plate): relay it to
  # our client, which renders the reveal / slab-raise. Everyone in the world converges on this truth.
  def handle_info({:world_wards, wards}, socket) do
    push(socket, "ward_state", %{wards: wards})
    {:noreply, socket}
  end


  # ── Social events, from our own user topic (Server.Friends.notify/2) ──

  def handle_info({:friends_changed}, socket) do
    push(socket, "friends", Social.snapshot(socket.assigns.user_id))
    {:noreply, socket}
  end

  def handle_info({:friend_request, from, name}, socket) do
    push(socket, "friend_request", %{from: from, name: name})
    {:noreply, socket}
  end

  def handle_info({:home_invite, from, name}, socket) do
    push(socket, "home_invite", %{from: from, name: name})
    {:noreply, socket}
  end

  def handle_info({:invite_answer, guest, name, accepted}, socket) do
    push(socket, "invite_answer", %{guest: guest, name: name, accepted: accepted})
    {:noreply, socket}
  end

  # We were sent out of a home (the owner sent us, closed it, removed or blocked us). Only acted on if
  # we're actually standing in that home; the client walks back to the Gateway.
  def handle_info({:evicted, world_id}, socket) do
    if socket.assigns[:world_id] == world_id, do: push(socket, "sent_home", %{})
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns do
      %{world_id: world_id, user_id: user_id} -> World.forget(world_id, user_id)
      _ -> :ok
    end

    :ok
  end

  @impl true
  def handle_in("identity", payload, socket) do
    # The name is the server's (FR-0): whatever the client sent is replaced with the player's own
    # generated name, so nobody can wear someone else's.
    identity =
      payload
      |> Map.take(["appearance", "companion_look", "companion_form"])
      |> Map.put("name", Map.get(socket.assigns, :name, "a wanderer"))

    # Remember how our companion looks, for the stand-in that naps at home while we're away (FR-5).
    Homes.set_resident(socket.assigns.user_id, identity)

    {:ok, _ref} =
      Presence.update(socket, socket.assigns.user_id, fn meta ->
        Map.put(meta, :identity, identity)
      end)

    {:noreply, socket}
  end

  def handle_in("state", payload, socket) do
    World.update_transform(socket.assigns.world_id, socket.assigns.user_id, payload)
    {:noreply, socket}
  end

  # A shared-world Ruin ward INTENT from this player's companion: "uncover" (its search nosed out a
  # plate) or "occupy" (it stepped onto / off a plate). The world process holds the authoritative ward
  # state, combines everyone's intents, and broadcasts the result back (handle_info {:world_wards}).
  # Server-stamped user_id, exactly like every other relayed action; unknown wards are ignored there.
  def handle_in("ward", payload, socket) do
    World.apply_ward(socket.assigns.world_id, socket.assigns.user_id, payload)
    {:noreply, socket}
  end

  # A glow-plant FLARE: this player touched a prop that blazes up when touched (the night world's
  # blooms), and everyone ELSE in the world should see it light too. Purely a relay — no state is kept,
  # the light fades on its own on every client — but only for a prop this world's spec actually marks
  # `"flare": true`, so a client can't spray arbitrary events at the room.
  def handle_in("flare", %{"prop" => prop_id}, socket) when is_binary(prop_id) do
    if flare_prop?(socket.assigns.definition, prop_id) do
      broadcast_from!(socket, "flared", %{prop: prop_id})
    end

    {:noreply, socket}
  end

  def handle_in("save", payload, socket) do
    Saves.store(socket.assigns.user_id, payload["companion"], payload["appearance"])
    {:noreply, socket}
  end

  # Buy a color from the shop. The purchase is server-authoritative (sink + grant, atomic, ledgered);
  # we just relay the outcome. On success the client updates its wallet + marks the color owned; on
  # failure it surfaces the reason. `item_def_id` may arrive as a number or a string (JSON).
  def handle_in("buy", %{"item_def_id" => raw_id}, socket) do
    user_id = socket.assigns.user_id

    case parse_item_def_id(raw_id) do
      :error ->
        push(socket, "buy_failed", %{item_def_id: raw_id, reason: "bad_item"})

      {:ok, item_def_id} ->
        case Economy.purchase(user_id, item_def_id) do
          {:ok, %{balance: balance}} ->
            push(socket, "bought", %{item_def_id: item_def_id, balance: balance, currency: @shop_currency})

          {:error, reason} ->
            push(socket, "buy_failed", %{item_def_id: item_def_id, reason: to_string(reason)})
        end
    end

    {:noreply, socket}
  end

  # Claim the reward for finishing the riverbank salamander hunt. The client reports how many of the
  # ten it found; the SERVER decides the payout (see @hunt_rewards), mints it, and confirms the new
  # balance — the same server-authoritative discipline as `buy`. The grant is honoured only in a world
  # that actually carries the hunt, so the reward can't be claimed from the Vale or the bazaar.
  def handle_in("hunt_complete", %{"found" => found}, socket) when is_integer(found) do
    user_id = socket.assigns.user_id
    amount = hunt_reward_amount(socket.assigns.definition, found)

    balance =
      if amount > 0 do
        case Economy.grant_currency(user_id, @shop_currency, amount,
               txn_type: "reward",
               context: %{"source" => "salamander_hunt", "found" => found}) do
          {:ok, new_balance} -> new_balance
          {:error, _reason} -> Economy.balance(user_id, @shop_currency)
        end
      else
        Economy.balance(user_id, @shop_currency)
      end

    push(socket, "hunt_reward", %{found: found, amount: amount, balance: balance, currency: @shop_currency})
    # Remember this visit's best hunt: the Riverbank's elder only shows for a perfect one (SecretReveal).
    {:noreply, assign(socket, :hunt_found, max(found, Map.get(socket.assigns, :hunt_found, 0)))}
  end

  # Claim the reward for reaching the heart of the hedge maze. The SERVER decides the payout (a flat
  # @maze_reward), mints it, and confirms the new balance — the same server-authoritative discipline as
  # the hunt. Honoured only in a world whose spec carries the maze goal, so it can't be claimed
  # elsewhere. (The client only sends this once per visit; even so, the grant is the maze's to make.)
  def handle_in("maze_complete", _payload, socket) do
    user_id = socket.assigns.user_id
    amount = maze_reward_amount(socket.assigns.definition)

    balance =
      if amount > 0 do
        case Economy.grant_currency(user_id, @shop_currency, amount,
               txn_type: "reward",
               context: %{"source" => "hedge_maze"}) do
          {:ok, new_balance} -> new_balance
          {:error, _reason} -> Economy.balance(user_id, @shop_currency)
        end
      else
        Economy.balance(user_id, @shop_currency)
      end

    push(socket, "maze_reward", %{amount: amount, balance: balance, currency: @shop_currency})
    {:noreply, socket}
  end

  # Claim a world SECRET (the thing each destination world hides; see Server.Discoveries). The SERVER
  # judges it: the claim is honoured only in a world whose spec authors that secret, and only while our
  # last reported position is at it, so it can't be claimed from another world or from across the maze.
  # A first find is recorded (and changes our home); a repeat is answered `new: false`. A refused
  # claim gets `secret_refused`, so the client can let the moment pass quietly.
  def handle_in("claim_secret", %{"id" => secret_id}, socket) when is_binary(secret_id) do
    %{user_id: user_id, world_id: world_id, definition: definition} = socket.assigns
    core = get_in(definition.spec, ["core"]) || %{}
    pos = World.snapshot(world_id) |> Map.get(user_id, %{}) |> Map.get("p")

    # How it becomes findable (Server.SecretReveal): a door that must be open, a perfect hunt this visit.
    reveal_ctx = %{wards: World.wards(world_id), hunt_found: Map.get(socket.assigns, :hunt_found, 0), hunt_goal: core["goal"] || %{}}

    if Discoveries.claimable?(core, secret_id, pos) and Server.SecretReveal.met?(core["secret"], reveal_ctx) do
      # S-4: was the companion beside us, and which friends were near (about a screen away)?
      transforms = World.snapshot(world_id)
      together = Discoveries.together?(Map.get(transforms, user_id, %{}))
      with_ids = Discoveries.nearby_friends(transforms, user_id, Friends.friend_ids(user_id))
      card = Discoveries.card_for(core["secret"], catalog_id(world_id), definition.name)

      {:ok, outcome} =
        Discoveries.record(user_id, secret_id, catalog_id(world_id), together: together, with_ids: with_ids, card: card)

      with_names = with_ids |> Profiles.names() |> Map.values() |> Enum.sort()
      push(socket, "secret_found", %{id: secret_id, new: outcome == :new, with: with_names})
    else
      push(socket, "secret_refused", %{id: secret_id})
    end

    {:noreply, socket}
  end

  # ── Friends, invites, visits and safety (FR-0..FR-5). The decisions live in Server.Friends /
  # Server.Homes / Server.Social; these clauses only route and answer. ──

  # A fresh generated name (FR-0). Friends' lists pick it up; peers see it on our next identity.
  def handle_in("reroll_name", _payload, socket) do
    user_id = socket.assigns.user_id
    name = Profiles.reroll_name(user_id)
    socket = assign(socket, :name, name)
    {:ok, _} = Presence.update(socket, user_id, fn meta -> put_in(meta, [:identity, "name"], name) end)
    push(socket, "profile", %{id: user_id, name: name, friend_code: Profiles.ensure(user_id).friend_code})
    Enum.each(Friends.friend_ids(user_id), &Friends.notify(&1, {:friends_changed}))
    {:noreply, socket}
  end

  # Ask someone to be friends (FR-2): a player we tapped (`to`), or a friend code (`code`).
  def handle_in("friend_request", payload, socket) do
    user_id = socket.assigns.user_id

    target =
      case payload do
        %{"to" => to} when is_binary(to) -> if Ecto.UUID.cast(to) == :error, do: nil, else: to
        %{"code" => code} when is_binary(code) -> Profiles.user_for_code(code)
        _ -> nil
      end

    reply =
      case target && Friends.request(user_id, target) do
        nil -> %{ok: false, reason: "no_such_code"}
        {:ok, :requested} ->
          Friends.notify(target, {:friend_request, user_id, socket.assigns.name})
          %{ok: true, status: "requested", name: Profiles.name(target)}

        {:ok, :friends} -> %{ok: true, status: "friends", name: Profiles.name(target)}
        {:error, reason} -> %{ok: false, reason: to_string(reason)}
      end

    push(socket, "friend_result", reply)
    {:noreply, socket}
  end

  def handle_in("friend_accept", %{"from" => from}, socket) when is_binary(from) do
    Friends.accept(socket.assigns.user_id, from)
    {:noreply, socket}
  end

  def handle_in("friend_decline", %{"from" => from}, socket) when is_binary(from) do
    Friends.decline(socket.assigns.user_id, from)
    {:noreply, socket}
  end

  # Remove a friend, quietly (FR-5). Neither of you can stay in the other's home on friendship alone.
  def handle_in("friend_remove", %{"id" => id}, socket) when is_binary(id) do
    user_id = socket.assigns.user_id
    Friends.remove(user_id, id)
    Social.evict(user_id, [id])
    Social.evict(id, [user_id])
    {:noreply, socket}
  end

  # Block someone (FR-5): ends friendship, requests, invites and passes both ways, and sends each of
  # you out of the other's home.
  def handle_in("block", %{"id" => id}, socket) when is_binary(id) do
    user_id = socket.assigns.user_id
    Friends.block(user_id, id)
    HomePasses.revoke(user_id, id)
    Social.evict(user_id, [id])
    Social.evict(id, [user_id])
    {:noreply, socket}
  end

  def handle_in("friends", _payload, socket) do
    push(socket, "friends", Social.snapshot(socket.assigns.user_id))
    {:noreply, socket}
  end

  # A one-off invite home (FR-3) for a player standing in this world with us. Blocks refuse quietly.
  def handle_in("invite_home", %{"to" => to}, socket) when is_binary(to) do
    user_id = socket.assigns.user_id
    here = Map.has_key?(Presence.list("world:" <> socket.assigns.world_id), to)

    if to != user_id and here and not Friends.blocked_either_way?(user_id, to) do
      HomePasses.offer(user_id, to)
      Friends.notify(to, {:home_invite, user_id, socket.assigns.name})
    end

    {:noreply, socket}
  end

  # Answer an invite. Accepting turns the live offer into a one-visit pass; the host is told either
  # way (an acceptance sends them home to meet you). An answer to an offer that doesn't exist (lapsed,
  # or never made) is ignored, so nobody can grant themselves a pass.
  def handle_in("invite_answer", %{"from" => owner, "accept" => accept}, socket) when is_binary(owner) do
    user_id = socket.assigns.user_id

    if HomePasses.take_offer(owner, user_id) do
      if accept == true, do: HomePasses.grant(owner, user_id)
      Friends.notify(owner, {:invite_answer, user_id, socket.assigns.name, accept == true})
      push(socket, "invite_result", %{owner: owner, accepted: accept == true, ok: true})
    else
      push(socket, "invite_result", %{owner: owner, accepted: false, ok: false})
    end

    {:noreply, socket}
  end

  # Send a visitor back to the Gateway (FR-5). Only from inside our own home.
  def handle_in("send_home", %{"id" => id}, socket) when is_binary(id) do
    user_id = socket.assigns.user_id
    if socket.assigns.world_id == HomeWorld.world_id(user_id) and id != user_id, do: Social.evict(user_id, [id])
    {:noreply, socket}
  end

  # Close (or reopen) our home to every visitor, friends included (FR-5). Closing sends anyone there out.
  def handle_in("set_home_closed", %{"closed" => closed}, socket) when is_boolean(closed) do
    user_id = socket.assigns.user_id
    Homes.set_closed(user_id, closed)

    if closed do
      HomePasses.revoke(user_id, :all)
      Social.evict(user_id)
    end

    push(socket, "friends", Social.snapshot(user_id))
    {:noreply, socket}
  end

  # The companion's keepsake choice (HS-3), decided on the client where its mind lives. The server
  # checks it's possible and stores it, so it stays stable until the companion changes its mind.
  def handle_in("set_keepsakes", %{"ids" => ids, "spots" => spots}, socket) do
    ok = match?({:ok, _}, Homes.set_keepsakes(socket.assigns.user_id, ids, spots))
    push(socket, "keepsakes_saved", %{ok: ok})
    {:noreply, socket}
  end

  # A JOURNAL (HS-5): ours, or the owner's of a home we may visit (or are standing in).
  def handle_in("journal", payload, socket) do
    user_id = socket.assigns.user_id
    owner = with o when is_binary(o) <- payload["owner"], {:ok, _} <- Ecto.UUID.cast(o), do: o, else: (_ -> user_id)

    if Social.can_read_journal?(user_id, owner, socket.assigns.world_id) do
      legacy = Map.get(HomeWorld.template(), "legacy_cards", %{})
      push(socket, "journal", %{owner: owner, name: Profiles.name(owner), entries: Discoveries.journal(owner, legacy)})
    end

    {:noreply, socket}
  end

  # Browse the world DIRECTORY (the Vale's Gateway): a page of listed worlds matching `q`, each with
  # how many people are in it right now (its Presence roster). The world we're asking from is left
  # out. `req` is echoed back untouched so the client can drop answers to searches it has since
  # replaced (typing fast fires several). Read-only — travelling is still just joining that world.
  def handle_in("list_worlds", payload, socket) when is_map(payload) do
    {cards, more} =
      Worlds.directory(
        q: payload["q"],
        limit: int_param(payload["limit"], 30),
        offset: int_param(payload["offset"], 0),
        exclude: socket.assigns.world_id
      )

    worlds = Enum.map(cards, &Map.put(&1, :players, map_size(Presence.list("world:" <> &1.world_id))))

    push(socket, "world_list", %{
      req: payload["req"],
      offset: int_param(payload["offset"], 0),
      worlds: worlds,
      more: more
    })

    {:noreply, socket}
  end

  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  # A world id as a catalog UUID (what a discovery remembers it was found in), or nil for a home.
  defp catalog_id(world_id) do
    case Ecto.UUID.cast(world_id) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp int_param(v, _default) when is_integer(v), do: v
  defp int_param(_v, default), do: default

  # The Ruin's ward defs from a world's spec (`ruin.wards`), or `[]` if it has no Ruin — what seeds the
  # shared ward state when the world process starts.
  defp ward_defs(definition) do
    get_in(definition.spec, ["core", "ruin", "wards"]) || []
  end

  # Whether `prop_id` names a prop in this world's spec that is flare-able (`"flare": true`).
  defp flare_prop?(definition, prop_id) do
    props = get_in(definition.spec, ["core", "props"])

    is_list(props) and
      Enum.any?(props, fn p -> is_map(p) and Map.get(p, "id") == prop_id and Map.get(p, "flare") == true end)
  end

  # A world's whole spec `core` map (or `%{}`) — what seeds the ambient-pal sim: its `ambient_pals` and
  # the geometry (trees/landmarks/props/ponds/collision/bounds) the pals steer around.
  defp ambient_core(definition) do
    get_in(definition.spec, ["core"]) || %{}
  end

  # The hunt payout for `found`, but only in a world whose spec carries the salamander hunt — elsewhere
  # there's nothing to reward, so it's always 0.
  defp hunt_reward_amount(definition, found) do
    if get_in(definition.spec, ["core", "goal", "type"]) == "find_salamanders" do
      Map.get(@hunt_rewards, found, 0)
    else
      0
    end
  end

  # The maze payout, but only in a world whose spec carries the "reach_center" goal — elsewhere
  # there's no maze to reward, so it's always 0.
  defp maze_reward_amount(definition) do
    if get_in(definition.spec, ["core", "goal", "type"]) == "reach_center" do
      @maze_reward
    else
      0
    end
  end

  # The wallet + shop stock for a user: balance of the shop currency, and every color definition with
  # an `owned` flag, flattened from its `base_attributes` into the flat shape the client renders.
  defp economy_snapshot(user_id) do
    owned = MapSet.new(Economy.wardrobe_def_ids(user_id))

    colors =
      for d <- Economy.color_catalog() do
        attrs = d.base_attributes || %{}

        %{
          item_def_id: d.item_def_id,
          name: d.name,
          color_slot: Map.get(attrs, "color_slot"),
          ramp: Map.get(attrs, "ramp"),
          swatch: Map.get(attrs, "swatch"),
          price: Map.get(attrs, "price"),
          owned: MapSet.member?(owned, d.item_def_id)
        }
      end

    %{currency: @shop_currency, balance: Economy.balance(user_id, @shop_currency), colors: colors}
  end

  defp parse_item_def_id(id) when is_integer(id), do: {:ok, id}

  defp parse_item_def_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_item_def_id(_), do: :error

  @impl true
  def handle_out("presence_diff", %{joins: joins, leaves: leaves}, socket) do
    {frames, known} = PresenceFrames.diff_to_frames(socket.assigns.user_id, socket.assigns.known, joins, leaves)
    Enum.each(frames, fn {event, payload} -> push(socket, event, payload) end)
    {:noreply, assign(socket, :known, known)}
  end
end
