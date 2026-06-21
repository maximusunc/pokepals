defmodule Server.MixProject do
  use Mix.Project

  # The minimal authoritative relay for Rung 4, step 1: assign ids, hold the roster, relay
  # presentation. No Ecto/Postgres, no Phoenix Presence, no Channels yet — those are later
  # Rung-4 steps. The runtime stack (Bandit + WebSock + Phoenix.PubSub) is the same one Phoenix
  # Channels ride on, so growing into Channels/Presence later is additive, not a rewrite.
  def project do
    [
      app: :server,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Server.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:websock_adapter, "~> 0.5"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1"}
    ]
  end
end
