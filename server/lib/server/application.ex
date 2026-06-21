defmodule Server.Application do
  @moduledoc """
  Boots the minimal authoritative relay: a PubSub hub for fan-out, the id/roster Hub, and a
  Bandit HTTP server that upgrades `GET /ws` to a WebSocket per client. No database, no Presence,
  no game simulation yet — this is Rung 4, step 1.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port = port()

    children = [
      # Live fan-out between connections (one node for now; this is the seam a multi-node /
      # Presence setup grows from).
      {Phoenix.PubSub, name: Server.PubSub},
      # The only shared state: id assignment + the roster.
      Server.Hub,
      # The HTTP/WebSocket listener.
      {Bandit, plug: Server.Router, scheme: :http, port: port}
    ]

    Logger.info("pokepals relay listening on ws://0.0.0.0:#{port}/ws")
    Supervisor.start_link(children, strategy: :one_for_one, name: Server.Supervisor)
  end

  # Listen on $PORT if set (handy for a hosted box), else 4000 — the client's DEFAULT_SERVER_URL.
  defp port do
    case System.get_env("PORT") do
      nil -> 4000
      str -> String.to_integer(str)
    end
  end
end
