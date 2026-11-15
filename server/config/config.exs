import Config

# Which repos `mix ecto.*` and the release migration task operate on.
config :server, ecto_repos: [Server.Repo]

# The Phoenix endpoint (transport seam). Bandit stays the HTTP server via the Phoenix adapter; the
# listen address/port come from runtime.exs (driven by $PORT). check_origin is off because the Godot
# NATIVE WebSocket client sends no Origin header. The browser (web export) build DOES send one — it's
# still accepted here; once the public origin is stable you may tighten this to an allowlist, e.g.
# `check_origin: ["https://your-box.ts.net"]`. The secret_key_base here is a dev/test default — prod
# overrides it from $SECRET_KEY_BASE in runtime.exs.
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

# MIME types for the served Godot web export. `.wasm` MUST be `application/wasm` or the browser
# refuses to streaming-compile it (Godot's loader uses `WebAssembly.instantiateStreaming`); `.pck`
# is Godot's opaque pack file. Modern `mime` already knows `wasm`, but we pin both to be safe.
# NOTE: changing `:mime` types requires recompiling that dep once — `mix deps.clean mime --build`.
config :mime, :types, %{
  "application/wasm" => ["wasm"],
  "application/octet-stream" => ["pck"]
}

# HOME BUILDING (docs/usable-items-design.md "Home building"). Every number here can also be set when the
# server boots, without a rebuild, from the environment (runtime.exs): CHOP_SECONDS, TREE_REGROW_SECONDS,
# PICKUP_REGROW_SECONDS, WOOD_PER_TREE, HOUSE_BUILD_SECONDS, HOUSE_WOOD, HOUSE_COINS.
#   chop_ms          how long a chop takes (0 = a tree falls in one swing)
#   tree_regrow_ms   how long a felled tree takes to grow back (shared by everyone in that world)
#   pickup_regrow_ms how long a picked-up stone or piece of driftwood takes to come back
#   wood_per_tree    how much wood one tree gives
config :server, Server.Harvest,
  chop_ms: 0,
  tree_regrow_ms: 300_000,
  pickup_regrow_ms: 180_000,
  wood_per_tree: 2

#   build_ms   how long the carpenter takes to build a house
#   wood/coins what she asks for it
config :server, Server.House,
  build_ms: 600_000,
  wood: 100,
  coins: 300

# Per-environment overrides (dev/test/prod). Runtime secrets live in runtime.exs.
import_config "#{config_env()}.exs"
