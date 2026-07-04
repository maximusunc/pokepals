defmodule Server.Endpoint do
  @moduledoc """
  The Phoenix endpoint — the transport seam for the client. P1 swaps the old raw Bandit/WebSock
  relay for **Phoenix Channels**: a `UserSocket` mounted at `/ws` (so the websocket lives at
  `/ws/websocket`), plus a tiny plug router for the `/health` check. Bandit is still the HTTP server
  (via `Bandit.PhoenixAdapter`) — only the session model moved up to Channels.
  """
  use Phoenix.Endpoint, otp_app: :server

  socket "/ws", Server.UserSocket,
    websocket: true,
    longpoll: false

  # Serve the Godot **Web export** (index.html/.js/.wasm/.pck/…) so the browser client and the `/ws`
  # socket live at the SAME origin — no CORS, no mixed-content, no second host to run. The client's
  # web build derives its `wss://` URL from the page origin (see `Net.default_server_url`), so
  # however a player reaches this server (LAN, a Tailscale Funnel's `*.ts.net`, …) the socket URL
  # matches automatically. Files are exported into `priv/static` (see `docs/web-export.md`); every
  # Godot output filename begins with `index`, so `only_matching` keeps this plug from ever shadowing
  # the `/health` and `/worlds` routes below. It's a no-op until the export exists. Must precede the
  # router so asset requests don't fall through to the catalog's `match _` 404.
  plug Plug.Static,
    at: "/",
    from: :server,
    gzip: true,
    only_matching: ~w(index favicon manifest)

  plug Server.Router
end
