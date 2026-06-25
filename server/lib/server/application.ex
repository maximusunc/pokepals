defmodule Server.Application do
  @moduledoc """
  Boots the authoritative server: the Postgres Repo, the PubSub hub for fan-out, the Presence roster,
  the shared World process (live transforms), and the Phoenix Endpoint (a `UserSocket` over WebSocket
  at `/ws`, plus the `/health` check). The transport is Phoenix Channels; Bandit serves HTTP under the
  endpoint.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # The DB first: the endpoint accepts connections the instant it starts, so a channel could
      # query immediately — the Repo must already be up.
      Server.Repo,
      # Live fan-out between connections; both the presence roster and the ~20 Hz state relay ride
      # on it.
      {Phoenix.PubSub, name: Server.PubSub},
      # The roster, as a CRDT (must start after PubSub, which it broadcasts diffs over).
      Server.Presence,
      # The shared world as a process: owns live transforms, fans them out over PubSub. One global
      # instance for now (becomes per-world later — see Server.World's deferred seams).
      Server.World,
      # The HTTP/WebSocket listener (Phoenix Channels over Bandit). Bind/port come from config.
      Server.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Server.Supervisor)
  end

  # Tell Phoenix to refresh the endpoint config on a hot code upgrade.
  @impl true
  def config_change(changed, _new, removed) do
    Server.Endpoint.config_change(changed, removed)
    :ok
  end
end
