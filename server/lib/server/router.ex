defmodule Server.Router do
  @moduledoc """
  The non-socket HTTP surface, plugged as the endpoint's fallback after the `/ws` socket: just a
  liveness check and a 404. The WebSocket upgrade is handled by `Server.UserSocket` (mounted at
  `/ws` by `Server.Endpoint`), not here.
  """
  use Plug.Router

  plug :match
  plug :dispatch

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
