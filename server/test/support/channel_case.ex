defmodule Server.ChannelCase do
  @moduledoc """
  Test case for the Phoenix Channel layer. Brings in `Phoenix.ChannelTest` (connect/3, join,
  push, assert_push/assert_broadcast) bound to `Server.Endpoint`, plus a DB sandbox so a channel
  process can hit Postgres.

  Channel tests run with `async: false` and a SHARED sandbox: `subscribe_and_join` spawns the
  channel in its own process, and shared mode lets that process see the test's connection (and the
  account it created at connect).
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import Server.ChannelCase

      @endpoint Server.Endpoint
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Server.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
