defmodule Server.Router do
  @moduledoc """
  The whole HTTP surface: a health check and the WebSocket upgrade. Every client connects to
  `GET /ws`, which hands the socket to `Server.PresenceRelay` (one handler process per client).
  """
  use Plug.Router

  plug :match
  plug :dispatch

  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(Server.PresenceRelay, [], timeout: 60_000)
    |> halt()
  end

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
