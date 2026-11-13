defmodule Server.Crafting do
  @moduledoc """
  CRAFTING, and the second usable item, the LANTERN (docs/usable-items-design.md, U-11 and U-14).

  The tinker in the bazaar makes things for you from what you bring, for a small fee. One recipe so far:
  a **lantern** from one sea-glass, one firefly and one piece of driftwood, plus 10 coins. Sea-glass and
  driftwood are reeled up while fishing (`Server.Fishing`); fireflies are invited along from the firefly
  glades in Dozewood (`at_firefly_glade?/2`). A lantern goes on your hotbar; carried, it lights the dark
  worlds (Underroot, Steamhollow's fog) and glows softly everywhere else. It's never needed anywhere.

  Each craft is ONE transaction through `Server.Economy`: every material consumed, the fee sunk, the made
  item granted, all ledgered, so nothing is lost or made from nothing. You can craft as many as you have
  the makings for (a spare can be traded).
  """

  alias Server.{Economy, Fishing, Hotbar, ItemDefinition, Repo}

  @lantern_id 4
  @firefly_id 250
  @driftwood_id 242
  @sea_glass_id 241

  @recipes [
    %{
      id: "lantern",
      makes: @lantern_id,
      needs: [{@sea_glass_id, 1}, {@firefly_id, 1}, {@driftwood_id, 1}],
      fee: 10,
      line: "A driftwood frame, a sea-glass window, and a firefly who'd like to stay."
    }
  ]

  # How near the tinker (or a firefly glade's edge) you must stand.
  @reach 90.0

  # At least this long between two fireflies, so a client can't fill a jar in a second.
  @firefly_gap_ms 4_000

  def lantern_id, do: @lantern_id
  def firefly_id, do: @firefly_id
  def recipes, do: @recipes
  def firefly_gap_ms, do: @firefly_gap_ms

  @doc "The lantern and the firefly (driftwood and sea-glass are catches, defined with Server.Fishing)."
  def item_defs do
    [
      %{
        item_def_id: @lantern_id,
        name: "Lantern",
        category: "tool",
        slot: "hand",
        stackable: false,
        base_attributes: %{"key" => "lantern", "use" => "light", "color" => [1.0, 0.8, 0.42]}
      },
      %{
        item_def_id: @firefly_id,
        name: "Firefly",
        category: "material",
        slot: nil,
        stackable: true,
        base_attributes: %{"key" => "firefly", "color" => [1.0, 0.92, 0.5]}
      }
    ]
  end

  @doc "Upsert crafting's item definitions (idempotent)."
  def seed_definitions do
    for attrs <- item_defs() do
      %ItemDefinition{}
      |> ItemDefinition.changeset(attrs)
      |> Repo.insert!(
        on_conflict: {:replace, [:name, :category, :slot, :stackable, :base_attributes]},
        conflict_target: :item_def_id
      )
    end

    :ok
  end

  @doc """
  The recipes as the client shows them: what each makes and needs (names, keys, colours), and the fee.
  Built from the item definitions in code, so it needs no database.
  """
  def recipes_view do
    defs = Map.new(Fishing.item_defs() ++ item_defs(), &{&1.item_def_id, &1})

    for r <- @recipes do
      %{
        id: r.id,
        fee: r.fee,
        line: r.line,
        makes: describe(defs, r.makes, 1),
        needs: for({id, n} <- r.needs, do: describe(defs, id, n))
      }
    end
  end

  defp describe(defs, id, n) do
    d = Map.get(defs, id, %{name: "something", category: "", base_attributes: %{}})
    attrs = d.base_attributes || %{}

    %{
      item_def_id: id,
      quantity: n,
      name: d.name,
      category: d.category,
      key: Map.get(attrs, "key", ""),
      color: Map.get(attrs, "color")
    }
  end

  @doc """
  Craft `recipe_id` for a user: in one transaction, consume every material, sink the fee, grant the made
  item and put it on the hotbar's first free slot (if it's a tool and not already there). `{:ok, %{item_def_id,
  name, balance}}` or `{:error, reason}` with nothing moved: `:no_recipe`, `:not_enough` (a material is
  missing) or `:insufficient_funds`.
  """
  @spec craft(Ecto.UUID.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def craft(user_id, recipe_id) do
    case Enum.find(@recipes, &(&1.id == recipe_id)) do
      nil -> {:error, :no_recipe}
      recipe -> do_craft(user_id, recipe)
    end
  end

  defp do_craft(user_id, recipe) do
    correlation_id = Ecto.UUID.generate()
    opts = [txn_type: "craft", context: %{"recipe" => recipe.id}, correlation_id: correlation_id]

    Repo.transaction(fn ->
      for {id, n} <- recipe.needs do
        case Economy.consume(user_id, id, n, opts) do
          {:ok, _left} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
      end

      balance =
        if recipe.fee > 0 do
          case Economy.sink_currency(user_id, "coins", recipe.fee, opts) do
            {:ok, b} -> b
            {:error, reason} -> Repo.rollback(reason)
          end
        else
          Economy.balance(user_id, "coins")
        end

      case Economy.grant_item(user_id, recipe.makes, opts) do
        {:ok, _item} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      made = Economy.item_definition(recipe.makes)
      if made && made.category == "tool", do: Hotbar.place(user_id, recipe.makes)

      %{item_def_id: recipe.makes, name: (made && made.name) || "something", balance: balance}
    end)
  end

  @doc "Whether `pos` is at a stall that crafts (`\"crafts\": true`): the tinker in the bazaar."
  @spec at_crafter?(map() | nil, list() | nil) :: boolean()
  def at_crafter?(core, [x, y]) when is_map(core) and is_number(x) and is_number(y) do
    props = Map.get(core, "props", [])

    is_list(props) and
      Enum.any?(props, fn p ->
        is_map(p) and Map.get(p, "crafts") == true and within?(Map.get(p, "position"), x, y, @reach)
      end)
  end

  def at_crafter?(_core, _pos), do: false

  @doc """
  Whether `pos` is in one of this world's firefly glades (the spec's `firefly_glades`: `[{position, radius}]`,
  Dozewood's).
  """
  @spec at_firefly_glade?(map() | nil, list() | nil) :: boolean()
  def at_firefly_glade?(core, [x, y]) when is_map(core) and is_number(x) and is_number(y) do
    glades = Map.get(core, "firefly_glades", [])

    is_list(glades) and
      Enum.any?(glades, fn g ->
        is_map(g) and within?(Map.get(g, "position"), x, y, num(Map.get(g, "radius"), 0.0) + 30.0)
      end)
  end

  def at_firefly_glade?(_core, _pos), do: false

  defp within?([px, py], x, y, r) when is_number(px) and is_number(py),
    do: :math.sqrt((x - px) * (x - px) + (y - py) * (y - py)) <= r

  defp within?(_p, _x, _y, _r), do: false

  defp num(v, _d) when is_number(v), do: v
  defp num(_v, d), do: d
end
