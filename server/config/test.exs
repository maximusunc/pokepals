import Config

# Each test runs in its own sandboxed, auto-rolled-back transaction (see Server.DataCase).
config :server, Server.Repo,
  url: System.get_env("DATABASE_URL") || "ecto://postgres:postgres@localhost/pokepals_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :logger, level: :warning
