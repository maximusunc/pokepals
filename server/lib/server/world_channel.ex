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

  Thereafter: `identity` → Presence.update; `state` → cast to this world's `Server.World`; `save` →
  persist by user_id; presence diffs → join/identity/leave frames. The sender id is always
  server-stamped (the player's user_id); clients never send their own id.
  """
  use Phoenix.Channel
  require Logger
  alias Server.{Economy, Presence, PresenceFrames, Saves, World, Worlds}

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

  @impl true
  def join("world:" <> world_id, payload, socket) when world_id != "" do
    case Worlds.get(world_id) do
      nil ->
        Logger.warning("rejected join for unknown world #{inspect(world_id)} — is the catalog seeded? (mix run priv/repo/seeds.exs)")
        {:error, %{reason: "unknown_world"}}

      definition ->
        World.ensure_started(world_id, ward_defs(definition), ambient_defs(definition))
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

    if etag == known_etag do
      push(socket, "world_spec_unchanged", %{world_id: world_id, version: definition.version, etag: etag})
    else
      push(socket, "world_spec", Worlds.client_view(definition))
    end

    topic = "world:" <> world_id
    Phoenix.PubSub.subscribe(Server.PubSub, World.state_topic(world_id))
    {:ok, _ref} = Presence.track(socket, user_id, %{identity: %{}})

    peers = PresenceFrames.peers(Presence.list(topic), user_id)
    known = MapSet.new(peers, & &1.id)
    push(socket, "welcome", %{id: user_id, peers: peers})

    save = Saves.load(user_id)
    push(socket, "load", %{companion: save.companion, appearance: save.appearance})

    # The economy snapshot — our wallet + the shop's color stock, each flagged owned. A per-USER
    # concern (same in every world); the bazaar's shop reads it, every other world just ignores it.
    push(socket, "economy", economy_snapshot(user_id))

    for {peer_id, transform} <- World.snapshot(world_id), peer_id != user_id do
      push(socket, "state", Map.put(transform, "id", peer_id))
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

  # A live transform from this world: push to our client unless it's our own echo.
  def handle_info({:world_state, from_user, transform}, socket) do
    if from_user == socket.assigns.user_id do
      {:noreply, socket}
    else
      push(socket, "state", Map.put(transform, "id", from_user))
      {:noreply, socket}
    end
  end

  # The shared Ruin ward state changed (someone's companion uncovered/weighted a plate): relay it to
  # our client, which renders the reveal / slab-raise. Everyone in the world converges on this truth.
  def handle_info({:world_wards, wards}, socket) do
    push(socket, "ward_state", %{wards: wards})
    {:noreply, socket}
  end

  # A tick of the world's ambient-pal sim: relay the batch of pal transforms to our client, which eases
  # each puppet toward its new spot. The same shared truth reaches every player, so pals are consistent.
  def handle_info({:world_ambient, pals}, socket) do
    push(socket, "ambient_state", %{pals: pals})
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
    identity = Map.take(payload, ["name", "appearance", "companion_look"])

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
    {:noreply, socket}
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

  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  # The Ruin's ward defs from a world's spec (`ruin.wards`), or `[]` if it has no Ruin — what seeds the
  # shared ward state when the world process starts.
  defp ward_defs(definition) do
    get_in(definition.spec, ["core", "ruin", "wards"]) || []
  end

  # The ambient-pal defs from a world's spec (`ambient_pals`), or `[]` if it has none — what seeds the
  # shared ambient-pal sim when the world process starts.
  defp ambient_defs(definition) do
    get_in(definition.spec, ["core", "ambient_pals"]) || []
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
