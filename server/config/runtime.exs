import Config

# Runtime configuration — evaluated at BOOT (for both `mix release` artifacts and plain `mix` runs),
# so it's the right place to read the environment. PORT is the single knob; the endpoint binds all
# interfaces by default so it's reachable across a LAN / from outside a container. A public
# deployment should sit behind a reverse proxy rather than widen this.
#
# Under :test there is no listener (config/test.exs sets `server: false`), so skip the http config.
if config_env() != :test do
  config :server, Server.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")]
end

# Home building's tunables, overridable at boot from the environment (defaults in config.exs). Seconds here,
# so `HOUSE_BUILD_SECONDS=60` makes a house take a minute.
seconds = fn name ->
  with v when v not in [nil, ""] <- System.get_env(name), do: String.to_integer(v) * 1000
end

integer = fn name ->
  with v when v not in [nil, ""] <- System.get_env(name), do: String.to_integer(v)
end

harvest =
  [
    chop_ms: seconds.("CHOP_SECONDS"),
    tree_regrow_ms: seconds.("TREE_REGROW_SECONDS"),
    pickup_regrow_ms: seconds.("PICKUP_REGROW_SECONDS"),
    wood_per_tree: integer.("WOOD_PER_TREE")
  ]
  |> Enum.reject(fn {_k, v} -> is_nil(v) end)

house =
  [
    build_ms: seconds.("HOUSE_BUILD_SECONDS"),
    wood: integer.("HOUSE_WOOD"),
    coins: integer.("HOUSE_COINS")
  ]
  |> Enum.reject(fn {_k, v} -> is_nil(v) end)

if config_env() != :test do
  if harvest != [], do: config(:server, Server.Harvest, harvest)
  if house != [], do: config(:server, Server.House, house)
end

# Database + secret. In prod both must be supplied; dev/test fall back to localhost defaults
# (config/dev.exs, config/test.exs) and the dev/test secret in config/config.exs.
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :server, Server.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate one with: mix phx.gen.secret
      """

  config :server, Server.Endpoint, secret_key_base: secret_key_base
end
