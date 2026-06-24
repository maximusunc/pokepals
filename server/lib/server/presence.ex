defmodule Server.Presence do
  @moduledoc """
  The roster, as a Phoenix.Presence — a CRDT over Phoenix.PubSub that tracks each connected client's
  process under the "world" topic, keyed by its assigned id, with the player's identity stashed in
  the metadata. It auto-detects disconnects (it monitors the tracked process, so even a hard crash
  produces a clean leave), dedupes, and is multi-node ready.

  We use Presence WITHOUT a Phoenix.Endpoint — it only needs a `pubsub_server`. `Server.PresenceRelay`
  translates Presence's join/leave/update diffs into the client's existing wire frames, so the Godot
  client never learns the roster changed implementation.
  """
  use Phoenix.Presence,
    otp_app: :server,
    pubsub_server: Server.PubSub
end
