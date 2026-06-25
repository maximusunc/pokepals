defmodule Server.MixProject do
  use Mix.Project

  # The authoritative server: authenticates by token (→ user_id), tracks the roster via
  # Phoenix.Presence, relays presentation over Phoenix Channels, and persists the companion/wardrobe
  # in Postgres via Ecto. The runtime stack is Phoenix Channels (over Bandit, via
  # Bandit.PhoenixAdapter) + Phoenix.PubSub/Presence + Ecto — a socket-only endpoint, no HTML.
  def project do
    [
      app: :server,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      releases: releases()
    ]
  end

  # Compile test/support (DataCase, etc.) only under MIX_ENV=test.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # `mix test` creates + migrates the test DB first (idempotent), so a fresh checkout just works.
  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end

  # `MIX_ENV=prod mix release` produces a self-contained OTP release under
  # _build/prod/rel/server with a predictable `bin/server` launcher — no Elixir needed on the
  # target host. See DEPLOYMENT.md.
  defp releases do
    [
      server: [
        include_executables_for: [:unix]
      ]
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
      {:phoenix_pubsub, "~> 2.1"},
      # Phoenix Channels (the client transport), plus Phoenix.Presence (the CRDT roster) and a
      # socket-only Endpoint served over Bandit (Bandit.PhoenixAdapter). No HTML/view layer.
      {:phoenix, "~> 1.7"},
      # Server-canonical persistence of the companion/wardrobe (jsonb keyed by the player's token).
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"}
    ]
  end
end
