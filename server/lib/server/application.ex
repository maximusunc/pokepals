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
    # Port comes from runtime.exs (driven by $PORT); default covers a bare `iex -S mix` with no
    # config loaded.
    port = Application.get_env(:server, :port, 4000)

    children = [
      # Live fan-out between connections (one node for now; this is the seam a multi-node /
      # Presence setup grows from).
      {Phoenix.PubSub, name: Server.PubSub},
      # The only shared state: id assignment + the roster.
      Server.Hub,
      # The HTTP/WebSocket listener. Bind ALL interfaces ({0,0,0,0}) so clients on other machines
      # (and from outside a container) can reach it — not just loopback.
      {Bandit, plug: Server.Router, scheme: :http, ip: {0, 0, 0, 0}, port: port}
    ]

    Logger.info("pokepals relay listening on ws://0.0.0.0:#{port}/ws")
    Supervisor.start_link(children, strategy: :one_for_one, name: Server.Supervisor)
  end
end
