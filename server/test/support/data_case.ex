defmodule Server.DataCase do
  @moduledoc """
  Test case for anything that touches the DB. Each test gets an isolated transaction that is rolled
  back at the end, so tests don't see each other's writes.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Server.Repo
      import Ecto
      import Ecto.Query
      import Server.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Server.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
