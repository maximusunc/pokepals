defmodule Server.Presence do
  @moduledoc """
  The roster, as a Phoenix.Presence — a CRDT over Phoenix.PubSub that tracks each connected client's
  process under the "world" topic, keyed by the player's `user_id`, with their identity stashed in
  the metadata. It auto-detects disconnects (it monitors the tracked process, so even a hard crash
  produces a clean leave), dedupes, and is multi-node ready.

  `Server.WorldChannel` translates Presence's join/leave/update diffs into the client's wire frames
  (via `Server.PresenceFrames`) in `handle_out("presence_diff", ...)`, so the client never learns the
  roster's implementation.
  """
  use Phoenix.Presence,
    otp_app: :server,
    pubsub_server: Server.PubSub
end
