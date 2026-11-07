defmodule Server.RouterPacksTest do
  @moduledoc "GET /worlds/:id/packs — what the web client asks before it joins a world."
  use Server.DataCase, async: false
  import Plug.Test
  alias Server.{Packs, Router, Worlds}

  setup do
    slug = "packed-#{System.unique_integer([:positive])}"
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: slug,
        name: "Packed World",
        display_types: ["2d"],
        version: 1,
        spec: %{"core" => %{}, "profiles" => %{"2d" => %{}}}
      })

    manifest = %{
      "packs" => %{
        "p" => %{"url" => "packs/p.0123456789ab.pck", "bytes" => 7, "sha256" => "ab", "probe" => "res://assets/x.png"}
      },
      "worlds" => %{slug => ["p"]}
    }

    path = Path.join(System.tmp_dir!(), "router-packs-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(manifest))
    Application.put_env(:server, :packs_manifest_path, path)
    Packs.reload()

    on_exit(fn ->
      Application.delete_env(:server, :packs_manifest_path)
      Packs.reload()
      File.rm(path)
    end)

    %{slug: slug, world_id: world_id}
  end

  defp get_packs(id) do
    conn = Router.call(conn(:get, "/worlds/#{id}/packs"), Router.init([]))
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  test "by UUID: the world's name and the packs it needs", %{world_id: world_id} do
    assert {200, %{"world_id" => ^world_id, "name" => "Packed World", "packs" => [pack]}} = get_packs(world_id)
    assert %{"id" => "p", "url" => "packs/p.0123456789ab.pck", "bytes" => 7, "sha256" => "ab"} = pack
  end

  test "by slug works too", %{slug: slug} do
    assert {200, %{"packs" => [%{"id" => "p"}]}} = get_packs(slug)
  end

  test "a world that needs no packs gets an empty list" do
    plain = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: plain,
        slug: "plain-#{System.unique_integer([:positive])}",
        name: "Plain",
        display_types: ["2d"],
        version: 1,
        spec: %{"core" => %{}, "profiles" => %{"2d" => %{}}}
      })

    assert {200, %{"packs" => []}} = get_packs(plain)
  end

  test "an unknown world is a 404" do
    assert {404, %{"error" => "not_found"}} = get_packs(Ecto.UUID.generate())
    assert {404, %{"error" => "not_found"}} = get_packs("no-such-slug")
  end
end
