defmodule Server.PacksTest do
  @moduledoc """
  World packs: which downloadable art packs a world needs, read from the manifest the web build
  writes (`priv/static/packs/manifest.json`). The lookup itself is pure; one test goes through a real
  manifest file to cover loading + caching.
  """
  use ExUnit.Case, async: false
  alias Server.Packs

  @manifest %{
    "format" => 1,
    "packs" => %{
      "nocthollow" => %{
        "url" => "packs/nocthollow.a72d188cf58d.pck",
        "bytes" => 123_984,
        "sha256" => "a72d188cf58d0112",
        "probe" => "res://assets/pals/driftray_0.png",
        "files" => 54
      },
      "kit-a-b" => %{
        "url" => "packs/kit-a-b.0123456789ab.pck",
        "bytes" => 10,
        "sha256" => "0123456789ab",
        "probe" => "res://assets/sprites/x.png"
      }
    },
    "worlds" => %{
      "nocthollow" => ["nocthollow"],
      "a" => ["kit-a-b"],
      "dangling" => ["no-such-pack", "kit-a-b"]
    }
  }

  test "a world gets the descriptors of the packs it needs" do
    assert [
             %{
               id: "nocthollow",
               url: "packs/nocthollow.a72d188cf58d.pck",
               bytes: 123_984,
               sha256: "a72d188cf58d0112",
               probe: "res://assets/pals/driftray_0.png"
             }
           ] = Packs.descriptors(@manifest, "nocthollow")
  end

  test "a world that needs nothing, or isn't known, gets an empty list" do
    assert Packs.descriptors(@manifest, "vale") == []
    assert Packs.descriptors(%{}, "vale") == []
  end

  test "a pack the manifest doesn't contain is skipped, not fatal" do
    assert [%{id: "kit-a-b"}] = Packs.descriptors(@manifest, "dangling")
  end

  describe "from a manifest file" do
    setup do
      path = Path.join(System.tmp_dir!(), "packs-manifest-#{System.unique_integer([:positive])}.json")
      File.write!(path, Jason.encode!(@manifest))
      previous = Application.get_env(:server, :packs_manifest_path)
      Application.put_env(:server, :packs_manifest_path, path)
      Packs.reload()

      on_exit(fn ->
        if previous,
          do: Application.put_env(:server, :packs_manifest_path, previous),
          else: Application.delete_env(:server, :packs_manifest_path)

        Packs.reload()
        File.rm(path)
      end)

      %{path: path}
    end

    test "for_world reads the file, and a nil slug (a home) needs nothing" do
      assert [%{id: "nocthollow"}] = Packs.for_world("nocthollow")
      assert Packs.for_world("vale") == []
      assert Packs.for_world(nil) == []
    end
  end

  test "no manifest file means no packs, and a later export is picked up" do
    missing = Path.join(System.tmp_dir!(), "no-such-manifest-#{System.unique_integer([:positive])}.json")
    Application.put_env(:server, :packs_manifest_path, missing)
    Packs.reload()
    assert Packs.for_world("nocthollow") == []

    File.write!(missing, Jason.encode!(@manifest))
    assert [%{id: "nocthollow"}] = Packs.for_world("nocthollow")

    Application.delete_env(:server, :packs_manifest_path)
    Packs.reload()
    File.rm(missing)
  end
end
