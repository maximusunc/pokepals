import Config

# Runtime configuration — evaluated at BOOT (for both `mix release` artifacts and plain `mix`
# runs), so it's the right place to read the environment. PORT is the single knob; the relay binds
# all interfaces by default (see application.ex) so it's reachable across a LAN / from outside a
# container. A public deployment should sit behind a reverse proxy rather than widen this.
config :server, port: String.to_integer(System.get_env("PORT") || "4000")
