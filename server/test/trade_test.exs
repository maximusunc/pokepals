defmodule Server.TradeTest do
  @moduledoc """
  The trade transaction (§6.4): atomic swaps, ledger with one correlation_id, and the anti-dupe
  re-verification. True row-lock concurrency isn't exercised here — the SQL sandbox serializes through
  one connection — but the structural guarantees (single transaction, deterministic lock order,
  in-transaction re-verify) are: a stale offer to move an already-moved item is rejected.
  """
  use Server.DataCase, async: true
  alias Server.{Accounts, Economy, ItemDefinition, LedgerEntry}

  setup do
    %ItemDefinition{}
    |> ItemDefinition.changeset(%{item_def_id: 1, name: "Straw Hat", category: "cosmetic", slot: "head"})
    |> Repo.insert!()

    {:ok, a} = Accounts.resolve_token("trade-a-#{System.unique_integer([:positive])}")
    {:ok, b} = Accounts.resolve_token("trade-b-#{System.unique_integer([:positive])}")
    {:ok, c} = Accounts.resolve_token("trade-c-#{System.unique_integer([:positive])}")
    %{a: a.user_id, b: b.user_id, c: c.user_id}
  end

  test "swaps an item for currency atomically, with a single correlation_id", ctx do
    {:ok, hat} = Economy.grant_item(ctx.a, 1)
    {:ok, _} = Economy.grant_currency(ctx.b, "gold", 50)

    assert {:ok, correlation_id} =
             Economy.execute_trade(%{
               a: ctx.a,
               b: ctx.b,
               a_items: [hat.item_instance_id],
               b_currency: %{"gold" => 30}
             })

    # The hat is now B's; the 30 gold is now A's.
    assert [owned] = Economy.inventory(ctx.b)
    assert owned.item_instance_id == hat.item_instance_id
    assert Economy.inventory(ctx.a) == []
    assert Economy.balance(ctx.a, "gold") == 30
    assert Economy.balance(ctx.b, "gold") == 20

    # Both legs share one correlation_id (item move + currency move).
    rows = Repo.all(from(l in LedgerEntry, where: l.correlation_id == ^correlation_id))
    assert length(rows) == 2
    assert Enum.any?(rows, &(&1.asset_kind == "item"))
    assert Enum.any?(rows, &(&1.asset_kind == "currency"))

    # Ledger still reconciles with balances after the trade.
    assert Economy.balance(ctx.a, "gold") == Economy.ledger_balance(ctx.a, "gold")
    assert Economy.balance(ctx.b, "gold") == Economy.ledger_balance(ctx.b, "gold")
  end

  test "rolls back entirely when a party can't afford their offer", ctx do
    {:ok, hat} = Economy.grant_item(ctx.a, 1)
    {:ok, _} = Economy.grant_currency(ctx.b, "gold", 10)

    assert {:error, {:insufficient_funds, _, "gold"}} =
             Economy.execute_trade(%{
               a: ctx.a,
               b: ctx.b,
               a_items: [hat.item_instance_id],
               b_currency: %{"gold" => 30}
             })

    # Nothing moved.
    assert [still_as] = Economy.inventory(ctx.a)
    assert still_as.item_instance_id == hat.item_instance_id
    assert Economy.balance(ctx.b, "gold") == 10
  end

  test "re-verification prevents a double-spend of the same item", ctx do
    {:ok, hat} = Economy.grant_item(ctx.a, 1)

    # First trade gives the hat to B.
    assert {:ok, _} = Economy.execute_trade(%{a: ctx.a, b: ctx.b, a_items: [hat.item_instance_id]})

    # A no longer owns it, so a second trade offering the same hat is rejected — no dupe.
    assert {:error, {:not_owned, _}} =
             Economy.execute_trade(%{a: ctx.a, b: ctx.c, a_items: [hat.item_instance_id]})

    assert [owned] = Economy.inventory(ctx.b)
    assert owned.item_instance_id == hat.item_instance_id
    assert Economy.inventory(ctx.c) == []
  end
end
