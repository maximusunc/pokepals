defmodule Server.Economy do
  @moduledoc """
  The economy — and the §0 WALL around it. This module is the SOLE gateway for mutating currency,
  inventory, equipped items, and the wardrobe. Two invariants it exists to guarantee:

    1. **Ledger-or-nothing.** Every currency or item MOVEMENT (mint, sink, trade) writes its
       `economy_ledger` row(s) INSIDE the same transaction as the mutation. Equip is the one mutation
       that writes no ledger — it changes presentation, not ownership.
    2. **No dupes.** A trade is a single transaction that locks the affected rows in a deterministic
       order (lower `user_id` first) and RE-VERIFIES ownership and balances under those locks, so a
       stale offer can never move an asset twice.

  Money is `BIGINT` (integer Elixir terms), never floats. Postgres is the source of truth — no
  in-memory/cache value is ever authoritative for currency or items.

  THE WALL (enforced from P4): creator/UGC/world code must NEVER call these tables directly, and must
  NEVER call the mint/sink/trade functions raw — platform-economy effects reach UGC only through a
  mediated, rate-limited, ledger-logged API (built in P4). For now this module is the platform's own
  trusted economy API.

  ── DEFERRED SEAMS (scale/abuse hardening — NOT built until the need is real) ──────────────────────
    * ITEM-DEF CACHE: `item_definition/1` reads Postgres every call. Item definitions are read-constantly,
      change-rarely — a per-node ETS cache (Cachex) belongs here. Add it when read volume demands it.
    * RATE LIMITING: trade confirms / mint endpoints want a limiter (Hammer, ETS-backed) to blunt abuse.
      The anti-DUPE guarantee is structural (single txn + locks + re-verify), independent of this; the
      limiter is defense-in-depth, added when there's a surface to abuse.
  ──────────────────────────────────────────────────────────────────────────────────────────────────
  """
  import Ecto.Query

  alias Server.{
    EquippedItem,
    InventoryItem,
    ItemDefinition,
    LedgerEntry,
    PlayerCurrency,
    Repo,
    Wardrobe
  }

  @type uuid :: Ecto.UUID.t()
  @type currency_map :: %{optional(String.t()) => non_neg_integer()}

  @typedoc """
  A trade to execute: the two parties and what each offers. `*_items` are inventory instance ids;
  `*_currency` is `%{currency_type => amount}`.
  """
  @type trade :: %{
          required(:a) => uuid(),
          required(:b) => uuid(),
          optional(:a_items) => [uuid()],
          optional(:b_items) => [uuid()],
          optional(:a_currency) => currency_map(),
          optional(:b_currency) => currency_map(),
          optional(:context) => map()
        }

  # ── Reads ──────────────────────────────────────────────────────────────────────────────────────

  @doc "The current balance of one currency for a user (0 if no row)."
  @spec balance(uuid(), String.t()) :: integer()
  def balance(user_id, currency_type) do
    case Repo.get_by(PlayerCurrency, user_id: user_id, currency_type: currency_type) do
      nil -> 0
      %PlayerCurrency{balance: balance} -> balance
    end
  end

  @doc "All inventory instances a user owns."
  @spec inventory(uuid()) :: [InventoryItem.t()]
  def inventory(user_id), do: Repo.all(from(i in InventoryItem, where: i.user_id == ^user_id))

  @doc "The user's equipped map, `%{slot => item_instance_id}`."
  @spec equipped(uuid()) :: %{optional(String.t()) => uuid()}
  def equipped(user_id) do
    from(e in EquippedItem, where: e.user_id == ^user_id, select: {e.slot, e.item_instance_id})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  An item definition by id. DEFERRED SEAM: this is the natural home for a per-node ETS cache
  (Cachex) — definitions are read-constantly and change-rarely — but it reads Postgres for now.
  """
  @spec item_definition(integer()) :: ItemDefinition.t() | nil
  def item_definition(item_def_id), do: Repo.get(ItemDefinition, item_def_id)

  @doc "The item_def_ids of the cosmetics a user owns by definition (their wardrobe unlocks)."
  @spec wardrobe_def_ids(uuid()) :: [integer()]
  def wardrobe_def_ids(user_id) do
    Repo.all(from(w in Wardrobe, where: w.user_id == ^user_id, select: w.item_def_id))
  end

  @doc "Every purchasable color definition (category `\"color\"`), ordered by id — the shop's stock."
  @spec color_catalog() :: [ItemDefinition.t()]
  def color_catalog do
    Repo.all(from(d in ItemDefinition, where: d.category == "color", order_by: d.item_def_id))
  end

  @doc """
  The balance for a user/currency RECONSTRUCTED from the ledger (credits to − debits from). Equals
  `balance/2` for any account only ever touched through this module — the audit invariant.
  """
  @spec ledger_balance(uuid(), String.t()) :: integer()
  def ledger_balance(user_id, currency_type) do
    credits = sum_ledger(:to_user, user_id, currency_type)
    debits = sum_ledger(:from_user, user_id, currency_type)
    credits - debits
  end

  # ── Mints / sinks (currency + items) ─────────────────────────────────────────────────────────────

  @doc "Mint currency into a user's balance (no `from_user`), writing a ledger row in the same txn."
  @spec grant_currency(uuid(), String.t(), pos_integer(), keyword()) ::
          {:ok, integer()} | {:error, term()}
  def grant_currency(user_id, currency_type, amount, opts \\ []) when amount > 0 do
    {txn_type, context, correlation_id} = ledger_opts(opts, "grant")

    Repo.transaction(fn ->
      bump_currency!(user_id, currency_type, amount)

      write_ledger!(%{
        txn_type: txn_type,
        from_user: nil,
        to_user: user_id,
        asset_kind: "currency",
        asset_ref: currency_type,
        amount: amount,
        context: context,
        correlation_id: correlation_id
      })

      balance(user_id, currency_type)
    end)
  end

  @doc "Burn currency from a user's balance (no `to_user`); rolls back if they can't afford it."
  @spec sink_currency(uuid(), String.t(), pos_integer(), keyword()) ::
          {:ok, integer()} | {:error, term()}
  def sink_currency(user_id, currency_type, amount, opts \\ []) when amount > 0 do
    {txn_type, context, correlation_id} = ledger_opts(opts, "sink")

    Repo.transaction(fn ->
      ensure_currency_rows!([user_id], [currency_type])
      lock_currencies!([user_id], [currency_type])
      if balance(user_id, currency_type) < amount, do: Repo.rollback(:insufficient_funds)

      bump_currency!(user_id, currency_type, -amount)

      write_ledger!(%{
        txn_type: txn_type,
        from_user: user_id,
        to_user: nil,
        asset_kind: "currency",
        asset_ref: currency_type,
        amount: amount,
        context: context,
        correlation_id: correlation_id
      })

      balance(user_id, currency_type)
    end)
  end

  @doc "Mint a new item instance to a user, writing a ledger row in the same txn."
  @spec grant_item(uuid(), integer(), keyword()) :: {:ok, InventoryItem.t()} | {:error, term()}
  def grant_item(user_id, item_def_id, opts \\ []) do
    quantity = Keyword.get(opts, :quantity, 1)
    attributes = Keyword.get(opts, :attributes, %{})
    {txn_type, context, correlation_id} = ledger_opts(opts, "grant")

    Repo.transaction(fn ->
      item =
        %InventoryItem{}
        |> InventoryItem.changeset(%{
          user_id: user_id,
          item_def_id: item_def_id,
          quantity: quantity,
          attributes: attributes
        })
        |> Repo.insert!()

      write_ledger!(%{
        txn_type: txn_type,
        from_user: nil,
        to_user: user_id,
        asset_kind: "item",
        asset_ref: item.item_instance_id,
        amount: quantity,
        context: context,
        correlation_id: correlation_id
      })

      item
    end)
  end

  # ── Purchase (shop): sink price + grant the wardrobe unlock, atomically, ledger-logged ───────────

  @doc """
  BUY a catalog cosmetic from the platform shop: in ONE transaction, sink its price and grant it into
  the player's `wardrobe` (owned-by-definition), writing the matching ledger rows under one
  `correlation_id`. Funds and ownership move together or not at all — the same ledger-or-nothing
  discipline as the mints/sinks above, just composed.

  The price + currency live in the definition's `base_attributes` (`"price"`, `"currency"`). Rolls
  back on an unknown/priceless def, a def that isn't for sale (only `category: "color"` today), a
  cosmetic already owned, or insufficient funds. Returns `{:ok, %{item_def_id, balance}}` (the new
  balance of the spent currency) or `{:error, reason}` with nothing moved.
  """
  @spec purchase(uuid(), integer()) ::
          {:ok, %{item_def_id: integer(), balance: integer()}} | {:error, term()}
  def purchase(user_id, item_def_id) do
    correlation_id = Ecto.UUID.generate()

    Repo.transaction(fn ->
      definition = item_definition(item_def_id)

      cond do
        is_nil(definition) -> Repo.rollback(:no_definition)
        definition.category != "color" -> Repo.rollback(:not_for_sale)
        true -> :ok
      end

      attrs = definition.base_attributes || %{}
      price = Map.get(attrs, "price")
      currency = Map.get(attrs, "currency", "coins")
      if not is_integer(price) or price < 0, do: Repo.rollback(:not_for_sale)

      if Repo.get_by(Wardrobe, user_id: user_id, item_def_id: item_def_id),
        do: Repo.rollback(:already_owned)

      # Guard the funds under lock before spending (mirrors sink_currency).
      ensure_currency_rows!([user_id], [currency])
      lock_currencies!([user_id], [currency])
      if balance(user_id, currency) < price, do: Repo.rollback(:insufficient_funds)

      if price > 0 do
        bump_currency!(user_id, currency, -price)

        write_ledger!(%{
          txn_type: "purchase",
          from_user: user_id,
          to_user: nil,
          asset_kind: "currency",
          asset_ref: currency,
          amount: price,
          context: %{"item_def_id" => item_def_id},
          correlation_id: correlation_id
        })
      end

      %Wardrobe{}
      |> Wardrobe.changeset(%{user_id: user_id, item_def_id: item_def_id})
      |> Repo.insert!()

      write_ledger!(%{
        txn_type: "purchase",
        from_user: nil,
        to_user: user_id,
        asset_kind: "item",
        asset_ref: Integer.to_string(item_def_id),
        amount: 1,
        context: %{"item_def_id" => item_def_id},
        correlation_id: correlation_id
      })

      %{item_def_id: item_def_id, balance: balance(user_id, currency)}
    end)
  end

  # ── Equip (§6.3): Postgres-first, lock + verify; NO ledger (ownership doesn't change) ─────────────

  @doc """
  Equip an owned instance into its slot. Locks the instance `FOR UPDATE`, verifies ownership and that
  the item's definition allows that slot, then upserts `equipped_items`. No ledger row — equipping
  changes presentation, not ownership.
  """
  @spec equip(uuid(), uuid(), String.t()) :: {:ok, EquippedItem.t()} | {:error, term()}
  def equip(user_id, item_instance_id, slot) do
    Repo.transaction(fn ->
      item =
        Repo.one(from(i in InventoryItem, where: i.item_instance_id == ^item_instance_id, lock: "FOR UPDATE"))

      cond do
        is_nil(item) -> Repo.rollback(:not_found)
        item.user_id != user_id -> Repo.rollback(:not_owned)
        true -> :ok
      end

      case item_definition(item.item_def_id) do
        nil -> Repo.rollback(:no_definition)
        %ItemDefinition{slot: nil} -> Repo.rollback(:not_equippable)
        %ItemDefinition{slot: def_slot} when def_slot != slot -> Repo.rollback(:wrong_slot)
        %ItemDefinition{} -> :ok
      end

      %EquippedItem{}
      |> EquippedItem.changeset(%{user_id: user_id, slot: slot, item_instance_id: item_instance_id})
      |> Repo.insert!(
        on_conflict: {:replace, [:item_instance_id, :updated_at]},
        conflict_target: [:user_id, :slot]
      )
    end)
  end

  # ── Trade (§6.4): one transaction, deterministic lock order, in-txn re-verification ──────────────

  @doc """
  Atomically swap items and/or currency between two players. Returns `{:ok, correlation_id}` (the id
  shared by every ledger row this trade wrote) or `{:error, reason}` with NOTHING moved.

  The three anti-dupe invariants (§6.4):
    1. ONE transaction — never "remove from A" then "add to B" separately.
    2. Deterministic lock order — rows locked `FOR UPDATE` ordered by `user_id` (then key), so two
       concurrent trades over the same rows can't deadlock.
    3. Re-verify under lock — ownership and balances are re-checked against the DB, never trusted from
       the (stale, non-authoritative) offer.
  """
  @spec execute_trade(trade()) :: {:ok, uuid()} | {:error, term()}
  def execute_trade(%{a: a, b: b} = trade) do
    a_items = trade |> Map.get(:a_items, []) |> Enum.uniq()
    b_items = trade |> Map.get(:b_items, []) |> Enum.uniq()
    a_currency = Map.get(trade, :a_currency, %{})
    b_currency = Map.get(trade, :b_currency, %{})
    context = Map.get(trade, :context, %{})
    correlation_id = Ecto.UUID.generate()

    Repo.transaction(fn ->
      # 1. Acquire locks in a deterministic global order (lower user_id first), so two concurrent
      #    trades over the same rows can't deadlock. Ensure receiver currency rows exist first so they
      #    can be locked; do every step over users in sorted order, and lock with ORDER BY.
      users = Enum.sort([a, b])
      types = Enum.uniq(Map.keys(a_currency) ++ Map.keys(b_currency))
      ensure_currency_rows!(users, types)
      lock_currencies!(users, types)
      lock_items!(a_items ++ b_items)

      # 2. Re-verify everything under lock (the offer is stale and not authoritative).
      a_rows = verify_owns!(a, a_items)
      b_rows = verify_owns!(b, b_items)
      verify_funds!(a, a_currency)
      verify_funds!(b, b_currency)

      # 3. Move items, then currency — each writes ledger rows sharing this correlation_id.
      move_items!(a_rows, a, b, correlation_id, context)
      move_items!(b_rows, b, a, correlation_id, context)
      move_currency!(a, b, a_currency, correlation_id, context)
      move_currency!(b, a, b_currency, correlation_id, context)

      correlation_id
    end)
  end

  # ── internals ───────────────────────────────────────────────────────────────────────────────────

  defp ledger_opts(opts, default_txn_type) do
    {
      Keyword.get(opts, :txn_type, default_txn_type),
      Keyword.get(opts, :context, %{}),
      Keyword.get(opts, :correlation_id, Ecto.UUID.generate())
    }
  end

  # Upsert a zero row if absent, then atomically add `delta` (may be negative). Caller guards the
  # balance for sinks; the DB CHECK is the backstop (a violation rolls the whole txn back).
  defp bump_currency!(user_id, currency_type, delta) do
    Repo.insert!(%PlayerCurrency{user_id: user_id, currency_type: currency_type, balance: 0},
      on_conflict: :nothing,
      conflict_target: [:user_id, :currency_type]
    )

    {1, _} =
      from(pc in PlayerCurrency, where: pc.user_id == ^user_id and pc.currency_type == ^currency_type)
      |> Repo.update_all(inc: [balance: delta], set: [updated_at: DateTime.utc_now()])

    :ok
  end

  defp ensure_currency_rows!(users, types) do
    for user_id <- users, currency_type <- types do
      Repo.insert!(%PlayerCurrency{user_id: user_id, currency_type: currency_type, balance: 0},
        on_conflict: :nothing,
        conflict_target: [:user_id, :currency_type]
      )
    end

    :ok
  end

  defp lock_currencies!(_users, []), do: []

  defp lock_currencies!(users, types) do
    Repo.all(
      from(pc in PlayerCurrency,
        where: pc.user_id in ^users and pc.currency_type in ^types,
        order_by: [pc.user_id, pc.currency_type],
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_items!([]), do: []

  defp lock_items!(item_ids) do
    Repo.all(
      from(i in InventoryItem,
        where: i.item_instance_id in ^item_ids,
        order_by: [i.user_id, i.item_instance_id],
        lock: "FOR UPDATE"
      )
    )
  end

  # Re-read the offered instances and confirm they all still exist AND belong to `user_id`.
  defp verify_owns!(_user_id, []), do: []

  defp verify_owns!(user_id, item_ids) do
    rows = Repo.all(from(i in InventoryItem, where: i.item_instance_id in ^item_ids))
    found = MapSet.new(rows, & &1.item_instance_id)
    requested = MapSet.new(item_ids)

    cond do
      not MapSet.equal?(found, requested) ->
        Repo.rollback({:missing_items, MapSet.to_list(MapSet.difference(requested, found))})

      Enum.any?(rows, &(&1.user_id != user_id)) ->
        Repo.rollback({:not_owned, user_id})

      true ->
        rows
    end
  end

  defp verify_funds!(user_id, currency_map) do
    Enum.each(currency_map, fn {currency_type, amount} ->
      cond do
        amount < 0 -> Repo.rollback({:negative_amount, currency_type})
        amount == 0 -> :ok
        balance(user_id, currency_type) < amount -> Repo.rollback({:insufficient_funds, user_id, currency_type})
        true -> :ok
      end
    end)
  end

  defp move_items!(rows, from_user, to_user, correlation_id, context) do
    Enum.each(rows, fn item ->
      {1, _} =
        from(i in InventoryItem, where: i.item_instance_id == ^item.item_instance_id)
        |> Repo.update_all(set: [user_id: to_user, updated_at: DateTime.utc_now()])

      write_ledger!(%{
        txn_type: "trade",
        from_user: from_user,
        to_user: to_user,
        asset_kind: "item",
        asset_ref: item.item_instance_id,
        amount: item.quantity,
        context: context,
        correlation_id: correlation_id
      })
    end)
  end

  defp move_currency!(from_user, to_user, currency_map, correlation_id, context) do
    Enum.each(currency_map, fn
      {_currency_type, 0} ->
        :ok

      {currency_type, amount} ->
        bump_currency!(from_user, currency_type, -amount)
        bump_currency!(to_user, currency_type, amount)

        write_ledger!(%{
          txn_type: "trade",
          from_user: from_user,
          to_user: to_user,
          asset_kind: "currency",
          asset_ref: currency_type,
          amount: amount,
          context: context,
          correlation_id: correlation_id
        })
    end)
  end

  defp write_ledger!(attrs) do
    %LedgerEntry{}
    |> LedgerEntry.changeset(attrs)
    |> Repo.insert!()
  end

  defp sum_ledger(field, user_id, currency_type) do
    from(l in LedgerEntry,
      where:
        field(l, ^field) == ^user_id and l.asset_kind == "currency" and l.asset_ref == ^currency_type
    )
    |> Repo.aggregate(:sum, :amount) || 0
  end
end
