defmodule Server.Release do
  @moduledoc """
  Database tasks for the packaged release, where Mix (and `mix ecto.migrate`) is unavailable.

  Run from the release root / inside the container:

      bin/server eval "Server.Release.migrate()"
      bin/server eval "Server.Release.seed()"
      bin/server eval "Server.Release.rollback(Server.Repo, 20260625000000)"
  """
  @app :server

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Run the (idempotent) seeds — most importantly the catalog's seed worlds, without which the client
  has nowhere to enter. Starts the Repo just for the duration, like `migrate/0`.
  """
  def seed do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(Server.Repo, fn _repo -> IO.puts(Server.Seeds.run()) end)
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
