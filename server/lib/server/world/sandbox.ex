defmodule Server.World.Sandbox do
  @moduledoc """
  The UGC sandbox data-access layer — the fence around creator-world data (§4, §6.5). Every function
  takes a bound `Server.World.Context` and reads `world_id` from it, so creator code can NEVER
  construct a cross-world query (§10). It enforces, in the same transaction as each write:

    * **Isolation** — `world_id` comes from the ctx, never from arguments.
    * **Quotas** — per-value (256 KiB), per-world bytes, and key-count limits (under a locked
      `world_quota` row).
    * **Validation** — if a `world_schemas` row exists for the key, the value is validated (a small
      JSON-Schema subset for now; see `Server.WorldSchema`).
    * **Concurrency** — optimistic via `version`; plus atomic `increment/6` and `list_append/3` so
      creators don't read-modify-write and clobber.

  Values are JSON OBJECTS (maps): a key is a namespace (e.g. "stats"), its fields live inside. The
  ONLY query surfaces are these KV ops and the bounded list pagination — arbitrary JSONB queries are
  never exposed to creators.

  Scopes: "player" (owner = user_id), "entity" (owner = entity id), "world" (owner = the sentinel
  `global_owner/0`, since a Postgres PK column can't be NULL).
  """
  import Ecto.Query

  alias Server.{Repo, WorldData, WorldListItem, WorldQuota, WorldSchema}
  alias Server.World.Context

  # The sentinel owner_id for world ("global") scope — a fixed nil-UUID so the composite PK is valid.
  @global_owner "00000000-0000-0000-0000-000000000000"
  # Per-value ceiling (256 KiB of encoded JSON).
  @max_value_bytes 262_144

  @type scope :: String.t()
  @type reason :: atom() | tuple()

  @doc "The sentinel owner_id used for world/global scope."
  @spec global_owner() :: Ecto.UUID.t()
  def global_owner, do: @global_owner

  # ── Reads ──────────────────────────────────────────────────────────────────────────────────────

  @doc "Read a value (or nil) for (scope, owner, key) within the ctx's world."
  @spec get(Context.t(), scope(), Ecto.UUID.t(), String.t()) :: map() | nil
  def get(%Context{world_id: world_id}, scope, owner_id, key) do
    case Repo.get_by(WorldData, world_id: world_id, scope: scope, owner_id: owner_id, key: key) do
      nil -> nil
      %WorldData{value: value} -> value
    end
  end

  # ── Writes ─────────────────────────────────────────────────────────────────────────────────────

  @doc """
  Upsert a JSON-object value. Opts: `:version` — if given, the write only applies when the stored
  version matches (else `{:error, {:conflict, current_version}}`); omit it for a blind upsert.
  Returns `{:ok, new_version}` or `{:error, reason}` (`:value_must_be_object`, `:value_too_large`,
  `{:schema_*, _}`, `:bytes_quota_exceeded`, `:key_quota_exceeded`, `{:conflict, _}`).
  """
  @spec set(Context.t(), scope(), Ecto.UUID.t(), String.t(), map(), keyword()) ::
          {:ok, integer()} | {:error, reason()}
  def set(%Context{world_id: world_id}, scope, owner_id, key, value, opts \\ []) do
    expected = Keyword.get(opts, :version)

    with :ok <- ensure_object(value),
         :ok <- ensure_value_size(value),
         :ok <- ensure_schema(world_id, key, value) do
      Repo.transaction(fn ->
        quota = ensure_and_lock_quota!(world_id)
        existing = lock_data_row(world_id, scope, owner_id, key)
        write_value!(world_id, scope, owner_id, key, value, existing, expected, quota)
      end)
    end
  end

  @doc """
  Atomically add `n` to a numeric `field` inside the object at (scope, owner, key), creating the
  row/field as needed. Serialized by a row lock, so concurrent increments don't clobber. Returns
  `{:ok, new_field_value}` or `{:error, reason}`.
  """
  @spec increment(Context.t(), scope(), Ecto.UUID.t(), String.t(), String.t(), number()) ::
          {:ok, number()} | {:error, reason()}
  def increment(%Context{world_id: world_id}, scope, owner_id, key, field, n) when is_number(n) do
    Repo.transaction(fn ->
      quota = ensure_and_lock_quota!(world_id)
      existing = lock_data_row(world_id, scope, owner_id, key)
      base = (existing && existing.value) || %{}
      current = Map.get(base, field, 0)
      unless is_number(current), do: Repo.rollback({:not_a_number, field})

      new_value = Map.put(base, field, current + n)
      rollback_unless_ok(ensure_value_size(new_value))
      rollback_unless_ok(ensure_schema(world_id, key, new_value))

      write_value!(world_id, scope, owner_id, key, new_value, existing, nil, quota)
      Map.get(new_value, field)
    end)
  end

  # ── Lists (bounded, append-only, paginated) ──────────────────────────────────────────────────────

  @doc "Append a JSON-object item to a named list. Returns `{:ok, id}` (the cursor) or `{:error, _}`."
  @spec list_append(Context.t(), String.t(), map()) :: {:ok, integer()} | {:error, reason()}
  def list_append(%Context{world_id: world_id}, name, item) do
    with :ok <- ensure_object(item),
         :ok <- ensure_value_size(item) do
      Repo.transaction(fn ->
        quota = ensure_and_lock_quota!(world_id)
        bytes = value_bytes(item)
        check_quota!(quota, bytes, 1)

        row =
          %WorldListItem{}
          |> WorldListItem.changeset(%{world_id: world_id, name: name, item: item})
          |> Repo.insert!()

        bump_quota!(world_id, bytes, 1)
        row.id
      end)
    end
  end

  @doc """
  A page of a named list in append order. `cursor` is the last id seen (nil/0 to start). Returns
  `%{items: [...], cursor: next_id | nil}` — `cursor` is nil when the page wasn't full (end reached).
  """
  @spec list_page(Context.t(), String.t(), integer() | nil, pos_integer()) ::
          %{items: [map()], cursor: integer() | nil}
  def list_page(%Context{world_id: world_id}, name, cursor, limit) do
    after_id = cursor || 0

    rows =
      Repo.all(
        from(li in WorldListItem,
          where: li.world_id == ^world_id and li.name == ^name and li.id > ^after_id,
          order_by: [asc: li.id],
          limit: ^limit
        )
      )

    next = if length(rows) == limit and rows != [], do: List.last(rows).id, else: nil
    %{items: Enum.map(rows, & &1.item), cursor: next}
  end

  # ── internals ───────────────────────────────────────────────────────────────────────────────────

  defp write_value!(world_id, scope, owner_id, key, value, nil, expected, quota) do
    # First write for this key.
    if expected not in [nil, 0], do: Repo.rollback({:conflict, 0})
    bytes = value_bytes(value)
    check_quota!(quota, bytes, 1)

    %WorldData{}
    |> WorldData.changeset(%{
      world_id: world_id,
      scope: scope,
      owner_id: owner_id,
      key: key,
      value: value,
      version: 1
    })
    |> Repo.insert!()

    bump_quota!(world_id, bytes, 1)
    1
  end

  defp write_value!(world_id, scope, owner_id, key, value, %WorldData{} = existing, expected, quota) do
    if expected != nil and existing.version != expected do
      Repo.rollback({:conflict, existing.version})
    end

    delta = value_bytes(value) - value_bytes(existing.value)
    check_quota!(quota, delta, 0)
    new_version = existing.version + 1

    {1, _} =
      from(d in WorldData,
        where:
          d.world_id == ^world_id and d.scope == ^scope and d.owner_id == ^owner_id and d.key == ^key
      )
      |> Repo.update_all(set: [value: value, version: new_version, updated_at: DateTime.utc_now()])

    bump_quota!(world_id, delta, 0)
    new_version
  end

  defp ensure_object(value) when is_map(value), do: :ok
  defp ensure_object(_), do: {:error, :value_must_be_object}

  defp ensure_value_size(value) do
    if value_bytes(value) <= @max_value_bytes, do: :ok, else: {:error, :value_too_large}
  end

  defp value_bytes(value), do: byte_size(Jason.encode!(value))

  defp ensure_and_lock_quota!(world_id) do
    Repo.insert!(%WorldQuota{world_id: world_id}, on_conflict: :nothing, conflict_target: :world_id)
    Repo.one!(from(q in WorldQuota, where: q.world_id == ^world_id, lock: "FOR UPDATE"))
  end

  defp lock_data_row(world_id, scope, owner_id, key) do
    Repo.one(
      from(d in WorldData,
        where:
          d.world_id == ^world_id and d.scope == ^scope and d.owner_id == ^owner_id and d.key == ^key,
        lock: "FOR UPDATE"
      )
    )
  end

  defp check_quota!(quota, byte_delta, key_delta) do
    cond do
      quota.bytes_used + byte_delta > quota.bytes_limit -> Repo.rollback(:bytes_quota_exceeded)
      quota.key_count + key_delta > quota.key_limit -> Repo.rollback(:key_quota_exceeded)
      true -> :ok
    end
  end

  defp bump_quota!(world_id, byte_delta, key_delta) do
    {1, _} =
      from(q in WorldQuota, where: q.world_id == ^world_id)
      |> Repo.update_all(
        inc: [bytes_used: byte_delta, key_count: key_delta],
        set: [updated_at: DateTime.utc_now()]
      )

    :ok
  end

  # ── schema validation (a small JSON-Schema subset; full JSON Schema is a future lib swap) ────────

  defp ensure_schema(world_id, key, value) do
    case Repo.get_by(WorldSchema, world_id: world_id, key: key) do
      nil -> :ok
      %WorldSchema{json_schema: schema} -> validate_against_schema(value, schema)
    end
  end

  defp validate_against_schema(value, schema) do
    with :ok <- check_type(value, Map.get(schema, "type")),
         :ok <- check_required(value, Map.get(schema, "required", [])) do
      check_properties(value, Map.get(schema, "properties", %{}))
    end
  end

  defp check_type(_value, nil), do: :ok

  defp check_type(value, type) do
    if json_type_matches?(value, type), do: :ok, else: {:error, {:schema_type, type}}
  end

  defp check_required(value, required) when is_map(value) do
    case Enum.reject(required, &Map.has_key?(value, &1)) do
      [] -> :ok
      missing -> {:error, {:schema_required, missing}}
    end
  end

  defp check_required(_value, []), do: :ok
  defp check_required(_value, _required), do: {:error, {:schema_required, :not_an_object}}

  defp check_properties(value, properties) when is_map(value) and map_size(properties) > 0 do
    Enum.reduce_while(properties, :ok, fn {field, spec}, _acc ->
      case Map.fetch(value, field) do
        # Absent fields are allowed unless listed in `required` (checked above).
        :error ->
          {:cont, :ok}

        {:ok, field_value} ->
          case check_type(field_value, Map.get(spec, "type")) do
            :ok -> {:cont, :ok}
            {:error, _} -> {:halt, {:error, {:schema_field, field}}}
          end
      end
    end)
  end

  defp check_properties(_value, _properties), do: :ok

  defp json_type_matches?(value, "object"), do: is_map(value)
  defp json_type_matches?(value, "array"), do: is_list(value)
  defp json_type_matches?(value, "string"), do: is_binary(value)
  defp json_type_matches?(value, "number"), do: is_number(value)
  defp json_type_matches?(value, "integer"), do: is_integer(value)
  defp json_type_matches?(value, "boolean"), do: is_boolean(value)
  defp json_type_matches?(value, "null"), do: is_nil(value)
  # Unknown type keyword → don't block (forward-compatible with richer schemas).
  defp json_type_matches?(_value, _type), do: true

  defp rollback_unless_ok(:ok), do: :ok
  defp rollback_unless_ok({:error, reason}), do: Repo.rollback(reason)
end
