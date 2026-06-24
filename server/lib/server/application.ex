defmodule Server.Application do
  @moduledoc """
  Boots the authoritative server: the Postgres Repo, a PubSub hub for fan-out, the Presence roster,
  the id Hub, and a Bandit HTTP server that upgrades `GET /ws` to a WebSocket per client.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Port comes from runtime.exs (driven by $PORT); default covers a bare `iex -S mix` with no
    # config loaded.
    port = Application.get_env(:server, :port, 4000)

    children = [
      # The DB first: Bandit accepts connections the instant it starts, so a handler could query
      # immediately — the Repo must already be up.
      Server.Repo,
      # Live fan-out between connections; both the presence roster and the ~20 Hz state relay ride
      # on it.
      {Phoenix.PubSub, name: Server.PubSub},
      # The roster, as a CRDT (must start after PubSub, which it broadcasts diffs over).
      Server.Presence,
      # Hands out unique per-connection ids (the roster key).
      Server.Hub,
      # The HTTP/WebSocket listener. Bind ALL interfaces ({0,0,0,0}) so clients on other machines
      # (and from outside a container) can reach it — not just loopback.
      {Bandit, plug: Server.Router, scheme: :http, ip: {0, 0, 0, 0}, port: port}
    ]

    Logger.info("pokepals relay listening on ws://0.0.0.0:#{port}/ws")
    Supervisor.start_link(children, strategy: :one_for_one, name: Server.Supervisor)
  end
end
