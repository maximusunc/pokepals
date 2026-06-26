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

  plug Server.Router
end
