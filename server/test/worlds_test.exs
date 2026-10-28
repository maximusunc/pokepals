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
    assert view.etag == Worlds.etag(view.spec)
  end

  test "etag is content-derived: stable for the same spec, changes when the spec changes" do
    a = attrs()
    {:ok, _} = Worlds.upsert(a)
    e1 = Worlds.etag(Worlds.get(a.world_id))

    assert is_binary(e1)
    # Re-deriving from identical content (any key order) yields the same token.
    assert Worlds.etag(%{"profiles" => %{"2d" => %{}}, "core" => %{}}) == e1

    # Editing the spec changes the etag — no version bump needed for the cache to invalidate.
    {:ok, _} = Worlds.upsert(%{a | spec: %{"core" => %{"x" => 1}, "profiles" => %{}}})
    assert Worlds.etag(Worlds.get(a.world_id)) != e1
  end

  test "list can filter by display type" do
    {:ok, _} = Worlds.upsert(attrs(%{name: "TwoD", display_types: ["2d"]}))
    {:ok, _} = Worlds.upsert(attrs(%{name: "ThreeD", display_types: ["3d"]}))

    names = Worlds.list(display_type: "3d") |> Enum.map(& &1.name)
    assert "ThreeD" in names
    refute "TwoD" in names
  end

  describe "directory" do
    # A unique word per test so other rows in the catalog (seeds, other tests) never collide.
    defp tag, do: "t#{System.unique_integer([:positive])}"

    test "lists listed public worlds as light cards (no spec), featured first" do
      t = tag()
      {:ok, _} = Worlds.upsert(attrs(%{name: "B #{t}", blurb: "a pond", tags: [t]}))
      {:ok, _} = Worlds.upsert(attrs(%{name: "A #{t}", tags: [t]}))
      {:ok, _} = Worlds.upsert(attrs(%{name: "Z #{t}", tags: [t], featured: true, accent: [0.1, 0.2, 0.3]}))

      {cards, more} = Worlds.directory(q: t)
      assert Enum.map(cards, & &1.name) == ["Z #{t}", "A #{t}", "B #{t}"]
      refute more

      [z | _] = cards
      assert z.featured
      assert z.accent == [0.1, 0.2, 0.3]
      refute Map.has_key?(z, :spec)
    end

    test "unlisted, private and inactive worlds stay out" do
      t = tag()
      {:ok, _} = Worlds.upsert(attrs(%{name: "Shown #{t}"}))
      {:ok, _} = Worlds.upsert(attrs(%{name: "Hub #{t}", listed: false}))
      {:ok, _} = Worlds.upsert(attrs(%{name: "Secret #{t}", visibility: "private"}))
      {:ok, _} = Worlds.upsert(attrs(%{name: "Gone #{t}", status: "archived"}))

      {cards, _} = Worlds.directory(q: t)
      assert Enum.map(cards, & &1.name) == ["Shown #{t}"]
    end

    test "q matches name, blurb or a tag, case-insensitively, and wildcards match literally" do
      t = tag()
      {:ok, _} = Worlds.upsert(attrs(%{name: "Mossy #{t}"}))
      {:ok, _} = Worlds.upsert(attrs(%{name: "Other", blurb: "a quiet #{t} glade"}))
      {:ok, _} = Worlds.upsert(attrs(%{name: "Tagged", tags: [String.upcase(t)]}))

      {cards, _} = Worlds.directory(q: "  #{String.upcase(t)} ")
      assert length(cards) == 3

      {cards, _} = Worlds.directory(q: "mossy " <> t)
      assert Enum.map(cards, & &1.name) == ["Mossy #{t}"]

      {cards, _} = Worlds.directory(q: t <> "%")
      assert cards == []
    end

    test "pages with limit/offset and reports whether more remain; exclude drops a world" do
      t = tag()
      ids =
        for n <- 1..3 do
          a = attrs(%{name: "#{n} #{t}", tags: [t]})
          {:ok, _} = Worlds.upsert(a)
          a.world_id
        end

      {page1, true} = Worlds.directory(q: t, limit: 2)
      {page2, false} = Worlds.directory(q: t, limit: 2, offset: 2)
      assert Enum.map(page1 ++ page2, & &1.name) == ["1 #{t}", "2 #{t}", "3 #{t}"]

      {cards, _} = Worlds.directory(q: t, exclude: hd(ids))
      assert Enum.map(cards, & &1.name) == ["2 #{t}", "3 #{t}"]
    end
  end
end
