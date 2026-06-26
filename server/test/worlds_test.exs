defmodule Server.WorldsTest do
  @moduledoc "The world catalog: upsert/get/list of server-hosted, versioned world definitions."
  use Server.DataCase, async: true
  alias Server.Worlds

  defp attrs(over \\ %{}) do
    Map.merge(
      %{
        world_id: Ecto.UUID.generate(),
        slug: "slug-#{System.unique_integer([:positive])}",
        name: "W",
        display_types: ["2d"],
        version: 1,
        spec: %{"core" => %{}, "profiles" => %{"2d" => %{}}}
      },
      over
    )
  end

  test "upsert then get / get_by_slug / version" do
    a = attrs()
    {:ok, _} = Worlds.upsert(a)

    assert Worlds.get(a.world_id).name == "W"
    assert Worlds.get_by_slug(a.slug).world_id == a.world_id
    assert Worlds.version(a.world_id) == 1
    assert Worlds.get(Ecto.UUID.generate()) == nil
  end

  test "upsert is idempotent and replaces by world_id" do
    a = attrs()
    {:ok, _} = Worlds.upsert(a)
    {:ok, _} = Worlds.upsert(%{a | name: "W2", version: 2})

    w = Worlds.get(a.world_id)
    assert w.name == "W2"
    assert w.version == 2
  end

  test "list returns public active worlds; client_view carries the spec" do
    a = attrs(%{name: "Alpha"})
    {:ok, _} = Worlds.upsert(a)

    assert "Alpha" in (Worlds.list() |> Enum.map(& &1.name))

    view = Worlds.client_view(Worlds.get(a.world_id))
    assert view.world_id == a.world_id
    assert view.version == 1
    assert view.spec == %{"core" => %{}, "profiles" => %{"2d" => %{}}}
  end

  test "list can filter by display type" do
    {:ok, _} = Worlds.upsert(attrs(%{name: "TwoD", display_types: ["2d"]}))
    {:ok, _} = Worlds.upsert(attrs(%{name: "ThreeD", display_types: ["3d"]}))

    names = Worlds.list(display_type: "3d") |> Enum.map(& &1.name)
    assert "ThreeD" in names
    refute "TwoD" in names
  end
end
