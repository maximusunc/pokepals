import Config

# Which repos `mix ecto.*` and the release migration task operate on.
config :server, ecto_repos: [Server.Repo]

# Keep the relay quiet-but-useful: connection lifecycle at :info, no debug spam at ~20 Hz.
config :logger, level: :info

# Per-environment overrides (dev/test/prod). Runtime secrets live in runtime.exs.
import_config "#{config_env()}.exs"
