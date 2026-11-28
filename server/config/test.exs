import Config

# Each test runs in its own sandboxed, auto-rolled-back transaction (see Server.DataCase).
config :server, Server.Repo,
  url: System.get_env("DATABASE_URL") || "ecto://postgres:postgres@localhost/gates_of_elyra_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# No HTTP listener under test — `Phoenix.ChannelTest` drives the socket/channel in-process.
config :server, Server.Endpoint, server: false

config :logger, level: :warning

# Fishing bites at once under test, so a channel test can cast and reel without sleeping.
config :server, Server.Fishing, wait_range: {0, 0}

# Channel tests connect with a device token directly (`connect(UserSocket, %{"token" => ...})`), skipping
# the POST /session ticket round trip. Compile-time, and only here: dev and prod accept tickets only.
config :server, Server.UserSocket, allow_token_param: true

# A replaced socket is closed a moment after it is told (Server.Sessions); tests needn't wait a second.
config :server, Server.Sessions, close_delay_ms: 50
