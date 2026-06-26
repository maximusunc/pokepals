defmodule Server.World.SandboxTest do
  @moduledoc """
  The UGC sandbox: KV round-trips, optimistic concurrency, atomic increment, schema validation,
  quota enforcement, bounded lists — and the §10 invariant that a context can only ever touch its
  own world. Exercised through the creator-facing `World.*` facade. world_id/owner are bare UUIDs
  (the sandbox is fenced — no FK to accounts).
  """
  use Server.DataCase, async: true

  alias Server.{WorldQuota, WorldSchema}
  alias Server.World.Context
  alias Server.World.{Entity, Global, Player}
  alias Server.World.List, as: Lists

  setup do
    %{ctx: Context.new(Ecto.UUID.generate()), user: Ecto.UUID.generate(), entity: Ecto.UUID.generate()}
  end

  describe "KV round-trips by scope" do
    test "player / global / entity values are stored and read back", %{ctx: ctx, user: user, entity: entity} do
      assert {:ok, 1} = Player.set(ctx, user, "stats", %{"wins" => 1})
      assert Player.get(ctx, user, "stats") == %{"wins" => 1}

      assert {:ok, 1} = Global.set(ctx, "weather", %{"sky" => "clear"})
      assert Global.get(ctx, "weather") == %{"sky" => "clear"}

      assert {:ok, 1} = Entity.set(ctx, entity, "door", %{"open" => false})
      assert Entity.get(ctx, entity, "door") == %{"open" => false}
    end

    test "a value must be a JSON object", %{ctx: ctx, user: user} do
      assert {:error, :value_must_be_object} = Player.set(ctx, user, "k", 5)
      assert {:error, :value_must_be_object} = Player.set(ctx, user, "k", [1, 2, 3])
    end
  end

  describe "optimistic concurrency (version)" do
    test "a matching version updates; a stale version conflicts; a blind set ignores version", %{ctx: ctx, user: user} do
      assert {:ok, 1} = Player.set(ctx, user, "k", %{"a" => 1})
      assert {:ok, 2} = Player.set(ctx, user, "k", %{"a" => 2}, version: 1)
      assert {:error, {:conflict, 2}} = Player.set(ctx, user, "k", %{"a" => 3}, version: 1)
      # No version given → blind upsert, bumps to 3.
      assert {:ok, 3} = Player.set(ctx, user, "k", %{"a" => 3})
    end

    test "a versioned first write to a missing key conflicts", %{ctx: ctx, user: user} do
      assert {:error, {:conflict, 0}} = Player.set(ctx, user, "fresh", %{"a" => 1}, version: 1)
    end
  end

  describe "atomic increment" do
    test "creates the field, then accumulates without clobbering", %{ctx: ctx, user: user} do
      assert {:ok, 1} = Player.increment(ctx, user, "stats", "coins", 1)
      assert {:ok, 6} = Player.increment(ctx, user, "stats", "coins", 5)
      assert Player.get(ctx, user, "stats") == %{"coins" => 6}
    end

    test "refuses to increment a non-numeric field", %{ctx: ctx, user: user} do
      {:ok, 1} = Player.set(ctx, user, "stats", %{"name" => "Fen"})
      assert {:error, {:not_a_number, "name"}} = Player.increment(ctx, user, "stats", "name", 1)
    end
  end

  describe "schema validation" do
    setup %{ctx: ctx} do
      Repo.insert!(%WorldSchema{
        world_id: ctx.world_id,
        key: "profile",
        json_schema: %{
          "type" => "object",
          "required" => ["name"],
          "properties" => %{"name" => %{"type" => "string"}, "age" => %{"type" => "integer"}}
        }
      })

      :ok
    end

    test "accepts a valid value and rejects missing-required / wrong-typed fields", %{ctx: ctx, user: user} do
      assert {:ok, 1} = Player.set(ctx, user, "profile", %{"name" => "Fen", "age" => 3})
      assert {:error, {:schema_required, ["name"]}} = Player.set(ctx, user, "profile", %{"age" => 3})
      assert {:error, {:schema_field, "age"}} = Player.set(ctx, user, "profile", %{"name" => "Fen", "age" => "x"})
    end

    test "a key without a registered schema accepts any object", %{ctx: ctx, user: user} do
      assert {:ok, 1} = Player.set(ctx, user, "freeform", %{"anything" => [1, 2, 3]})
    end
  end

  describe "quotas" do
    test "rejects a value over the per-value size limit", %{ctx: ctx, user: user} do
      big = %{"blob" => String.duplicate("x", 300_000)}
      assert {:error, :value_too_large} = Player.set(ctx, user, "k", big)
    end

    test "rejects a write that would exceed the per-world byte limit", %{ctx: ctx, user: user} do
      Repo.insert!(%WorldQuota{world_id: ctx.world_id, bytes_limit: 5})
      assert {:error, :bytes_quota_exceeded} = Player.set(ctx, user, "k", %{"a" => 1})
    end

    test "rejects a write that would exceed the key-count limit", %{ctx: ctx, user: user} do
      Repo.insert!(%WorldQuota{world_id: ctx.world_id, key_limit: 0})
      assert {:error, :key_quota_exceeded} = Player.set(ctx, user, "k", %{"a" => 1})
    end
  end

  describe "lists" do
    test "append then page through in order with a cursor", %{ctx: ctx} do
      {:ok, _} = Lists.append(ctx, "log", %{"t" => "a"})
      {:ok, _} = Lists.append(ctx, "log", %{"t" => "b"})
      {:ok, _} = Lists.append(ctx, "log", %{"t" => "c"})

      page1 = Lists.page(ctx, "log", nil, 2)
      assert page1.items == [%{"t" => "a"}, %{"t" => "b"}]
      assert page1.cursor != nil

      page2 = Lists.page(ctx, "log", page1.cursor, 2)
      assert page2.items == [%{"t" => "c"}]
      assert page2.cursor == nil
    end
  end

  describe "isolation (§10): a context can only touch its own world" do
    test "another world's context cannot read this world's data", %{ctx: ctx, user: user} do
      other = Context.new(Ecto.UUID.generate())

      {:ok, _} = Player.set(ctx, user, "secret", %{"v" => 1})
      {:ok, _} = Global.set(ctx, "weather", %{"sky" => "clear"})

      assert Player.get(other, user, "secret") == nil
      assert Global.get(other, "weather") == nil
      # And the same key in another world is independent, not a collision.
      assert {:ok, 1} = Global.set(other, "weather", %{"sky" => "storm"})
      assert Global.get(ctx, "weather") == %{"sky" => "clear"}
    end
  end
end
