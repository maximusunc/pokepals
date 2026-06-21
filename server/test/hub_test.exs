defmodule Server.HubTest do
  @moduledoc """
  The Hub is the server-authoritative core (id assignment + roster), so it's the part most worth
  a fast unit test. The app already starts a singleton Hub during `mix test`, so these assert
  relative invariants (ids increase, the roster reflects joins/identities/drops) rather than
  absolute ids — robust no matter what else has touched the shared instance.
  """
  use ExUnit.Case, async: false
  alias Server.Hub

  test "assigns increasing ids, reports who's present, and tracks identity + drop" do
    {id1, peers1} = Hub.join()
    {id2, peers2} = Hub.join()

    assert is_list(peers1)
    assert id2 > id1, "each connection gets a fresh, increasing id"
    assert Enum.any?(peers2, fn p -> p.id == id1 end), "a later joiner sees the earlier one in its roster"

    # put_identity (a cast) is enqueued before the following join (a call) from this same process,
    # so the GenServer has applied it by the time join runs.
    Hub.put_identity(id1, %{"name" => "Mossfen"})
    {_id3, peers3} = Hub.join()
    entry = Enum.find(peers3, fn p -> p.id == id1 end)
    assert entry.identity == %{"name" => "Mossfen"}, "the stored identity rides along in the roster"

    Hub.drop(id1)
    {_id4, peers4} = Hub.join()
    refute Enum.any?(peers4, fn p -> p.id == id1 end), "a dropped connection leaves the roster"
  end
end
