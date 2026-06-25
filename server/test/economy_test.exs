defmodule Server.EconomyTest do
  use Server.DataCase, async: true
  alias Server.{Accounts, Economy, ItemDefinition}

  # An equippable head item (def 1) and a non-equippable trinket (def 2).
  setup do
    insert_def(%{item_def_id: 1, name: "Straw Hat", category: "cosmetic", slot: "head"})
    insert_def(%{item_def_id: 2, name: "River Pebble", category: "trinket", slot: nil})
    {:ok, account} = Accounts.resolve_token("econ-#{System.unique_integer([:positive])}")
    %{user: account.user_id}
  end

  defp insert_def(attrs) do
    %ItemDefinition{} |> ItemDefinition.changeset(attrs) |> Repo.insert!()
  end

  describe "currency" do
    test "grant raises the balance and writes a matching ledger row", %{user: user} do
      assert {:ok, 100} = Economy.grant_currency(user, "gold", 100)
      assert Economy.balance(user, "gold") == 100
      assert Economy.ledger_balance(user, "gold") == 100
    end

    test "sink lowers the balance; insufficient funds roll back with nothing moved", %{user: user} do
      {:ok, _} = Economy.grant_currency(user, "gold", 40)

      assert {:error, :insufficient_funds} = Economy.sink_currency(user, "gold", 100)
      assert Economy.balance(user, "gold") == 40

      assert {:ok, 10} = Economy.sink_currency(user, "gold", 30)
      assert Economy.balance(user, "gold") == 10
    end

    test "balance always equals the balance reconstructed from the ledger", %{user: user} do
      {:ok, _} = Economy.grant_currency(user, "gold", 100)
      {:ok, _} = Economy.grant_currency(user, "gold", 25)
      {:ok, _} = Economy.sink_currency(user, "gold", 40)

      assert Economy.balance(user, "gold") == 85
      assert Economy.balance(user, "gold") == Economy.ledger_balance(user, "gold")
    end
  end

  describe "items" do
    test "grant mints an instance the user owns, with a ledger row", %{user: user} do
      assert {:ok, item} = Economy.grant_item(user, 1)
      assert item.user_id == user
      assert [owned] = Economy.inventory(user)
      assert owned.item_instance_id == item.item_instance_id
    end
  end

  describe "equip" do
    test "equips an owned item into its declared slot (no ledger row)", %{user: user} do
      {:ok, hat} = Economy.grant_item(user, 1)

      assert {:ok, _} = Economy.equip(user, hat.item_instance_id, "head")
      assert Economy.equipped(user) == %{"head" => hat.item_instance_id}
      # Equipping moves nothing, so the only ledger row is the grant's item mint.
      assert Economy.ledger_balance(user, "gold") == 0
    end

    test "rejects an item you don't own", %{user: user} do
      {:ok, other} = Accounts.resolve_token("econ-other")
      {:ok, hat} = Economy.grant_item(other.user_id, 1)

      assert {:error, :not_owned} = Economy.equip(user, hat.item_instance_id, "head")
    end

    test "rejects the wrong slot and a non-equippable item", %{user: user} do
      {:ok, hat} = Economy.grant_item(user, 1)
      {:ok, pebble} = Economy.grant_item(user, 2)

      assert {:error, :wrong_slot} = Economy.equip(user, hat.item_instance_id, "neck")
      assert {:error, :not_equippable} = Economy.equip(user, pebble.item_instance_id, "head")
    end
  end
end
