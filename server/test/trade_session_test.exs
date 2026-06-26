defmodule Server.TradeSessionTest do
  @moduledoc """
  The coordination layer: a session collects both offers and confirms, then executes through
  `Server.Economy`. async: false + shared sandbox so the session process can reach the DB.
  """
  use Server.DataCase, async: false
  alias Server.{Accounts, Economy, ItemDefinition, TradeSession}

  setup do
    %ItemDefinition{}
    |> ItemDefinition.changeset(%{item_def_id: 1, name: "Straw Hat", category: "cosmetic", slot: "head"})
    |> Repo.insert!()

    {:ok, a} = Accounts.resolve_token("ts-a-#{System.unique_integer([:positive])}")
    {:ok, b} = Accounts.resolve_token("ts-b-#{System.unique_integer([:positive])}")
    %{a: a.user_id, b: b.user_id}
  end

  test "two confirms execute the swap; the second confirm returns the result", ctx do
    {:ok, hat} = Economy.grant_item(ctx.a, 1)
    {:ok, _} = Economy.grant_currency(ctx.b, "gold", 50)

    {:ok, session} = TradeSession.start_link(a: ctx.a, b: ctx.b)

    assert :ok = TradeSession.offer(session, ctx.a, %{items: [hat.item_instance_id]})
    assert :ok = TradeSession.offer(session, ctx.b, %{currency: %{"gold" => 30}})

    assert :waiting = TradeSession.confirm(session, ctx.a)
    assert {:ok, _correlation_id} = TradeSession.confirm(session, ctx.b)

    # The trade went through Economy: hat to B, 30 gold to A.
    assert [owned] = Economy.inventory(ctx.b)
    assert owned.item_instance_id == hat.item_instance_id
    assert Economy.balance(ctx.a, "gold") == 30
    assert Economy.balance(ctx.b, "gold") == 20

    # Session stops itself after executing.
    refute Process.alive?(session)
  end

  test "a new offer clears standing confirms (you confirm what you currently see)", ctx do
    {:ok, hat} = Economy.grant_item(ctx.a, 1)

    {:ok, session} = TradeSession.start_link(a: ctx.a, b: ctx.b)
    :ok = TradeSession.offer(session, ctx.a, %{items: [hat.item_instance_id]})

    assert :waiting = TradeSession.confirm(session, ctx.a)

    # B changes the offer table — this clears A's standing confirm.
    :ok = TradeSession.offer(session, ctx.b, %{currency: %{}})

    # So B confirming alone is still :waiting; A must re-confirm what it now sees.
    assert :waiting = TradeSession.confirm(session, ctx.b)
    assert {:ok, _correlation_id} = TradeSession.confirm(session, ctx.a)

    # The (re-confirmed) trade executed: the hat moved to B.
    assert [owned] = Economy.inventory(ctx.b)
    assert owned.item_instance_id == hat.item_instance_id
  end
end
