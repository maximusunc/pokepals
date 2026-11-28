import Config

# Local development DB. Override with DATABASE_URL (see runtime.exs) if your Postgres differs.
config :server, Server.Repo,
  url: System.get_env("DATABASE_URL") || "ecto://postgres:postgres@localhost/gates_of_elyra_dev",
  pool_size: 10
