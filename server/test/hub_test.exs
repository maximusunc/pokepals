defmodule Server.HubTest do
  @moduledoc """
  The Hub is now just a monotonic id counter (the roster moved to Server.Presence). The app starts a
  singleton Hub during `mix test`, so this asserts the relative invariant — ids strictly increase and
  never repeat — rather than absolute values.
  """
  use ExUnit.Case, async: false
  alias Server.Hub

  test "hands out strictly increasing, unique ids" do
    a = Hub.next_id()
    b = Hub.next_id()
    c = Hub.next_id()

    assert is_integer(a) and a > 0
    assert b > a and c > b
    assert length(Enum.uniq([a, b, c])) == 3
  end
end
