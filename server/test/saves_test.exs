defmodule Server.SavesTest do
  use Server.DataCase, async: true
  alias Server.Saves

  test "a brand-new player has no save" do
    assert Saves.load("nobody") == nil
  end

  test "store then load round-trips the companion + appearance blobs" do
    {:ok, _} = Saves.store("tok-1", %{"bond" => 0.5}, %{"equipped" => %{"hat" => "base:hat"}})

    assert Saves.load("tok-1") == %{
             companion: %{"bond" => 0.5},
             appearance: %{"equipped" => %{"hat" => "base:hat"}}
           }
  end

  test "storing again upserts (last write wins) rather than erroring on the same token" do
    {:ok, _} = Saves.store("tok-2", %{"bond" => 0.1}, %{})
    {:ok, _} = Saves.store("tok-2", %{"bond" => 0.9}, %{"colors" => %{"skin" => "warm"}})

    assert Saves.load("tok-2") == %{
             companion: %{"bond" => 0.9},
             appearance: %{"colors" => %{"skin" => "warm"}}
           }
  end
end
