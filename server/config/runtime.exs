import Config

# Runtime configuration — evaluated at BOOT (for both `mix release` artifacts and plain `mix`
# runs), so it's the right place to read the environment. PORT is the single knob; the relay binds
# all interfaces by default (see application.ex) so it's reachable across a LAN / from outside a
# container. A public deployment should sit behind a reverse proxy rather than widen this.
config :server, port: String.to_integer(System.get_env("PORT") || "4000")

# Database. In prod the URL must be supplied; dev/test fall back to localhost defaults in
# config/dev.exs and config/test.exs. The `url:` is auto-parsed (ecto://USER:PASS@HOST:PORT/DB).
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
end
