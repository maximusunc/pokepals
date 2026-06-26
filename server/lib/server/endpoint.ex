defmodule Server.Endpoint do
  @moduledoc """
  The Phoenix endpoint — the transport seam for the client. P1 swaps the old raw Bandit/WebSock
  relay for **Phoenix Channels**: a `UserSocket` mounted at `/ws` (so the websocket lives at
  `/ws/websocket`), plus a tiny plug router for the `/health` check. Bandit is still the HTTP server
  (via `Bandit.PhoenixAdapter`) — only the session model moved up to Channels.
  """
  use Phoenix.Endpoint, otp_app: :server

  # `max_frame_size` is an abuse guard: it bounds how big any single client frame may be (state
  # transforms are tiny; the largest legit frame is a `save` blob). Without it a frame is unbounded,
  # so one socket could ship a multi-MB frame and force the BEAM to buffer it. 128 KB is the outer
  # cap; `Server.WorldChannel` enforces a tighter, app-level limit on `save` specifically.
  socket "/ws", Server.UserSocket,
    websocket: [max_frame_size: 128 * 1024],
    longpoll: false

  plug Server.Router
end
