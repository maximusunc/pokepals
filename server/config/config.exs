import Config

# Which repos `mix ecto.*` and the release migration task operate on.
config :server, ecto_repos: [Server.Repo]

# The Phoenix endpoint (transport seam). Bandit stays the HTTP server via the Phoenix adapter; the
# listen address/port come from runtime.exs (driven by $PORT). check_origin is off because the Godot
# native WebSocket client sends no Origin header. The secret_key_base here is a dev/test default —
# prod overrides it from $SECRET_KEY_BASE in runtime.exs.
config :server, Server.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  pubsub_server: Server.PubSub,
  check_origin: false,
  server: true,
  secret_key_base: "dev_only_secret_key_base_change_me_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Keep the server quiet-but-useful: connection lifecycle at :info, no debug spam at ~20 Hz.
config :logger, level: :info

# Phoenix uses Jason for JSON (channel payloads, etc.).
config :phoenix, :json_library, Jason

# Per-environment overrides (dev/test/prod). Runtime secrets live in runtime.exs.
import_config "#{config_env()}.exs"
