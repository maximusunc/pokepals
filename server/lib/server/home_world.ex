defmodule Server.HomeWorld do
  @moduledoc """
  A player's HOME WORLD: their own small glade, which reflects who they've become by wandering (H6,
  H7, HS-1..HS-6 in docs/home-world-and-secrets-design.md). It's the server's per-player world: not a
  catalog row, but a spec built on demand and joined on `"world:home:" <> owner_user_id` (world id
  `"home:" <> owner_user_id`).

  What shapes it, from a template (`priv/home/home.json`):

    * **The base glade**, cozy even with nothing in it.
    * **Keepsake spots**: the bond opens 3 to 7 of them, and the glade widens a little with each one
      past 3 (`growth.per_spot`), so size follows the relationship, not the number of worlds visited.
    * **Keepsakes**: the ones the companion chose (stored in `Server.Homes`, favourite first) stand at
      those spots. Each is examinable; its line is written from the companion's point of view.
    * **Qualities**: every find carries 1 to 3 of eight core qualities. The home leans toward your mix
      of them, gently: a capped tint, a share of each quality's living things in proportion to how
      much of your finds carry it, a little more ambient life, and, only once a quality is a clear
      part of you, its feature.

  The journal is the unbounded record (`Server.Discoveries.journal/1`); the home never tries to hold
  every world. Display-only: the player never arranges anything.
  """
  alias Server.{Discoveries, Homes, Profiles, WorldDefinition}

  @list_keys ~w(props trees flowers ponds landmarks)

  @doc "The home world id for an owner: `\"home:\" <> owner_user_id`."
  @spec world_id(Ecto.UUID.t()) :: String.t()
  def world_id(owner_id), do: "home:" <> owner_id

  @doc """
  The owner's home as an in-memory `WorldDefinition` (never persisted), so the channel treats it like
  any catalog world. `viewer_id` decides one thing: a visitor (not the owner) also gets the
  `resident`, the owner's companion napping at home, which the client shows while the owner is away.
  """
  @spec definition(Ecto.UUID.t(), Ecto.UUID.t() | nil) :: WorldDefinition.t()
  def definition(owner_id, viewer_id \\ nil) when is_binary(owner_id) do
    template = template()
    home = Homes.get(owner_id)

    state = %{
      owner_id: owner_id,
      owner_name: Profiles.name(owner_id),
      spots: home.spots,
      keepsakes: home.keepsakes,
      cards: Discoveries.cards(owner_id, Map.get(template, "legacy_cards", %{})),
      resident: if(viewer_id != owner_id, do: home.resident, else: %{})
    }

    %WorldDefinition{
      world_id: world_id(owner_id),
      slug: nil,
      name: "Home",
      owner_id: owner_id,
      display_types: ["2d"],
      version: 1,
      spec: %{"core" => build_core(template, state), "profiles" => %{"2d" => %{}}},
      visibility: "private",
      listed: false
    }
  end

  @doc """
  Build a home's spec core. Pure (no database), so it's testable on its own. `state` carries:
  `spots` (3..7), `keepsakes` (chosen discovery ids, favourite first), `cards` (every find, as an
  ordered list of `{id, card}`), and optionally `owner_id`, `owner_name` and `resident`.
  """
  @spec build_core(map(), map()) :: map()
  def build_core(%{"base" => base} = template, state) do
    spots = state |> Map.get(:spots, 3) |> max(3) |> min(7)
    cards = Map.get(state, :cards, [])
    card_map = Map.new(cards)

    core =
      base
      |> grow(spots, template)
      |> place_keepsakes(Map.get(state, :keepsakes, []), card_map, spots, template)
      |> apply_qualities(qualities_of(cards), length(cards), template)

    home = %{
      "owner_id" => Map.get(state, :owner_id),
      "owner_name" => Map.get(state, :owner_name, ""),
      "spots" => spots,
      "keepsakes" => Map.get(state, :keepsakes, []) |> Enum.filter(&Map.has_key?(card_map, &1)) |> Enum.take(spots),
      # Every find, for the owner's companion to choose from (KeepsakeChoice, on the client).
      "finds" => Enum.map(cards, fn {id, card} -> finds_entry(id, card) end)
    }

    resident = Map.get(state, :resident, %{})
    core = Map.put(core, "home", if(map_size(resident) > 0, do: Map.put(home, "resident", resident), else: home))

    trees = Server.WorldBorder.positions(Map.get(core, "bounds"), Map.get(core, "border", %{}))
    Map.put(core, "border_trees", trees)
  end

  # The glade widens by `growth.per_spot` on every side for each keepsake spot past 3.
  defp grow(core, spots, template) do
    [gx, gy | _] = get_in(template, ["growth", "per_spot"]) || [0, 0]
    extra = spots - 3

    case Map.get(core, "bounds") do
      %{"min" => [x0, y0 | _], "max" => [x1, y1 | _]} ->
        bounds = %{"min" => [x0 - gx * extra, y0 - gy * extra], "max" => [x1 + gx * extra, y1 + gy * extra]}
        regions = Enum.map(Map.get(core, "regions", []), &Map.merge(&1, bounds))
        core |> Map.put("bounds", bounds) |> Map.put("regions", regions)

      _ ->
        core
    end
  end

  # Each chosen keepsake stands at its spot (favourite first), as an examinable prop.
  defp place_keepsakes(core, keepsakes, card_map, spots, template) do
    positions = Map.get(template, "keepsake_spots", [])

    props =
      keepsakes
      |> Enum.filter(&Map.has_key?(card_map, &1))
      |> Enum.take(min(spots, length(positions)))
      |> Enum.with_index()
      |> Enum.map(fn {id, i} ->
        k = Map.get(card_map[id], "keepsake", %{})

        %{
          "id" => "keepsake_" <> id,
          "type" => Map.get(k, "type", "chime_stone"),
          "position" => Enum.at(positions, i),
          "color" => Map.get(k, "color", [0.7, 0.7, 0.7]),
          "label" => Map.get(k, "label", "a keepsake"),
          "lore" => Map.get(k, "line", ""),
          "tags" => ["keepsake"],
          "interactive" => true,
          "keepsake" => id,
          "favourite" => i == 0
        }
      end)

    Map.update(core, "props", props, &(&1 ++ props))
  end

  @doc "How many of the finds carry each quality: `%{quality => count}`."
  @spec qualities_of([{String.t(), map()}]) :: %{String.t() => non_neg_integer()}
  def qualities_of(cards) do
    cards
    |> Enum.flat_map(fn {_id, card} -> card |> Map.get("qualities", []) |> Enum.uniq() |> Enum.take(3) end)
    |> Enum.frequencies()
  end

  @doc """
  How strongly each quality shows, 0..1: its share of all quality mentions, ramped up gently as finds
  accumulate (a single find shows a little; `quality_ramp_finds` finds show fully).
  """
  @spec strengths(%{String.t() => non_neg_integer()}, non_neg_integer(), map()) :: %{String.t() => float()}
  def strengths(counts, finds, template) do
    total = counts |> Map.values() |> Enum.sum()
    ramp = min(1.0, finds / max(1, Map.get(template, "quality_ramp_finds", 6)))

    if total == 0,
      do: %{},
      else: Map.new(counts, fn {q, n} -> {q, n / total * (0.4 + 0.6 * ramp)} end)
  end

  defp apply_qualities(core, counts, finds, template) do
    defs = Map.get(template, "qualities", %{})
    strengths = strengths(Map.take(counts, Map.keys(defs)), finds, template)
    total = counts |> Map.values() |> Enum.sum()
    min_count = Map.get(template, "feature_min_count", 2)
    min_share = Map.get(template, "feature_min_share", 0.25)

    # Deterministic order (alphabetical), so the same finds always build the same home.
    Enum.reduce(Enum.sort(strengths), core, fn {q, s}, acc ->
      d = Map.fetch!(defs, q)
      featured = counts[q] >= min_count and counts[q] / max(total, 1) >= min_share

      acc
      |> add_living(Map.get(d, "living", %{}), s)
      |> add_life(Map.get(d, "life", %{}), s)
      |> then(fn a -> if featured, do: add_feature(a, Map.get(d, "feature", %{})), else: a end)
    end)
    |> apply_tint(strengths, defs, Map.get(template, "tint_cap", 0.08))
  end

  # A share of the quality's living things, in proportion to its strength (at least one once it shows).
  defp add_living(core, living, s) do
    Enum.reduce(living, core, fn {key, items}, acc ->
      n = items |> length() |> Kernel.*(s) |> Float.ceil() |> trunc()
      add_list(acc, key, Enum.take(items, n))
    end)
  end

  defp add_feature(core, feature) do
    core =
      Enum.reduce(@list_keys, core, fn key, acc ->
        case Map.get(feature, key) do
          list when is_list(list) -> add_list(acc, key, list)
          _ -> acc
        end
      end)

    if Map.get(feature, "fireflies_always"), do: put_life(core, "fireflies", "always", true), else: core
  end

  # More butterflies / fireflies: added to the shared art direction's counts through the home's own
  # `art` block (deep-merged over data/art.json on the client).
  defp add_life(core, life, s) do
    Enum.reduce(life, core, fn {kind, n}, acc ->
      current = get_in(acc, ["art", "entities", "ambient_life", kind, "count"]) || base_count(kind)
      put_life(acc, kind, "count", current + round(n * s))
    end)
  end

  # data/art.json's defaults, so a home's added life builds on them rather than replacing them.
  defp base_count("fireflies"), do: 16
  defp base_count("butterflies"), do: 6
  defp base_count(_), do: 0

  defp put_life(core, kind, key, value) do
    art = Map.get(core, "art", %{})
    entities = Map.get(art, "entities", %{})
    life = Map.get(entities, "ambient_life", %{})
    k = life |> Map.get(kind, %{}) |> Map.put(key, value)
    Map.put(core, "art", Map.put(art, "entities", Map.put(entities, "ambient_life", Map.put(life, kind, k))))
  end

  defp apply_tint(core, strengths, defs, cap) do
    delta =
      Enum.reduce(strengths, [0.0, 0.0, 0.0], fn {q, s}, [r, g, b] ->
        [dr, dg, db | _] = get_in(defs, [q, "tint"]) || [0, 0, 0]
        [r + dr * s, g + dg * s, b + db * s]
      end)
      |> Enum.map(&(&1 |> max(-cap) |> min(cap)))

    case get_in(core, ["atmosphere", "day_tint"]) do
      [r, g, b | _] ->
        [dr, dg, db] = delta
        put_in(core, ["atmosphere", "day_tint"], [Float.round(r + dr, 3), Float.round(g + dg, 3), Float.round(b + db, 3)])

      _ ->
        core
    end
  end

  defp add_list(core, _key, []), do: core
  defp add_list(core, key, items), do: Map.update(core, key, items, &(&1 ++ items))

  defp finds_entry(id, card) do
    k = Map.get(card, "keepsake", %{})

    %{
      "id" => id,
      "label" => Map.get(k, "label", ""),
      "temperament" => Map.get(k, "temperament", %{}),
      "together" => Map.get(card, "together", false)
    }
  end

  @doc "The home template, read from `priv/home/home.json`."
  @spec template() :: map()
  def template do
    :server
    |> Application.app_dir("priv/home/home.json")
    |> File.read!()
    |> Jason.decode!()
  end
end
