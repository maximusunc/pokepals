defmodule Server.HomeWorld do
  @moduledoc """
  A player's HOME WORLD: their own small glade, built on demand from the discoveries they've found.
  It's the server's first PER-PLAYER world: not a catalog row, but a spec generated for one owner and
  joined on the topic `"world:home:" <> owner_user_id` (its world id is `"home:" <> owner_user_id`).

  The shape comes from a template (`priv/home/home.json`):

    * `base` is the empty glade. It's a complete world spec core, cozy on its own (HW-2).
    * `discoveries` maps each world secret's id to what it adds at home. Its list keys (`props`,
      `hedges`, `trees`, `flowers`, `paths`, `regions`, `ponds`) are appended to the base's, and the
      bounds widen to take in its `area`. So the glade grows where each find settles, and the border
      treeline (baked here, like the catalog seeds) moves out with it.

  Display-only (H2): the player never arranges anything. Because the spec is regenerated from the
  discovery record, its content etag changes the moment a new secret is found, and the client
  re-fetches its home on the next visit with no extra plumbing.
  """
  alias Server.{Discoveries, WorldDefinition}

  @list_keys ~w(props hedges trees flowers paths regions ponds)

  @doc "The home world id for an owner: `\"home:\" <> owner_user_id`."
  @spec world_id(Ecto.UUID.t()) :: String.t()
  def world_id(owner_id), do: "home:" <> owner_id

  @doc """
  The owner's home as an in-memory `WorldDefinition` (never persisted), so the channel can treat it
  exactly like a catalog world: same spec delivery, same etag caching.
  """
  @spec definition(Ecto.UUID.t()) :: WorldDefinition.t()
  def definition(owner_id) when is_binary(owner_id) do
    core = build_core(template(), Discoveries.list(owner_id))

    %WorldDefinition{
      world_id: world_id(owner_id),
      slug: nil,
      name: "Home",
      owner_id: owner_id,
      display_types: ["2d"],
      version: 1,
      spec: %{"core" => core, "profiles" => %{"2d" => %{}}},
      visibility: "private",
      listed: false
    }
  end

  @doc """
  Build a home's spec core from a template and the owner's discovery ids (in the order found). Pure,
  so it's testable without the database. Ids the template doesn't know are skipped.
  """
  @spec build_core(map(), [String.t()]) :: map()
  def build_core(%{"base" => base} = template, discovery_ids) do
    additions = Map.get(template, "discoveries", %{})

    core =
      discovery_ids
      |> Enum.uniq()
      |> Enum.flat_map(fn id -> List.wrap(Map.get(additions, id)) end)
      |> Enum.reduce(base, &grow/2)
      |> Map.put("discoveries", Enum.filter(Enum.uniq(discovery_ids), &Map.has_key?(additions, &1)))

    trees = Server.WorldBorder.positions(Map.get(core, "bounds"), Map.get(core, "border", %{}))
    Map.put(core, "border_trees", trees)
  end

  # Fold one discovery's additions into the home: append its lists, widen the bounds to its area.
  defp grow(addition, core) do
    core =
      Enum.reduce(@list_keys, core, fn key, acc ->
        case Map.get(addition, key) do
          list when is_list(list) -> Map.update(acc, key, list, &(&1 ++ list))
          _ -> acc
        end
      end)

    case Map.get(addition, "area") do
      %{"min" => _, "max" => _} = area -> Map.update(core, "bounds", area, &union(&1, area))
      _ -> core
    end
  end

  defp union(%{"min" => [ax0, ay0 | _], "max" => [ax1, ay1 | _]}, %{"min" => [bx0, by0 | _], "max" => [bx1, by1 | _]}) do
    %{"min" => [min(ax0, bx0), min(ay0, by0)], "max" => [max(ax1, bx1), max(ay1, by1)]}
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
