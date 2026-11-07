defmodule Server.Packs do
  @moduledoc """
  The WORLD PACKS the web client downloads on demand.

  The browser build ships a small base (everything the Vale and every player's home need) and keeps
  each other world's own art in a separate pack, fetched the first time the player goes there. The
  build (`pokepals/tools/packs/build_packs.py`, run by `build-web.sh`) writes the packs and a manifest
  into `priv/static/packs/`:

      {"format": 1,
       "packs":  {"nocthollow": {"url": "packs/nocthollow.a72d188cf58d.pck", "bytes": 123984,
                                 "sha256": "...", "probe": "res://assets/pals/driftray_0.png", ...}},
       "worlds": {"nocthollow": ["nocthollow"]}}

  `worlds` is keyed by world SLUG. This module reads that file and answers one question: which packs
  does this world need? The world channel adds the answer to the `world_spec` / `world_spec_unchanged`
  it pushes. It is deliberately NOT part of the spec: the spec's content etag is the client's cache
  validator, and a rebuilt pack must not make every cached world look edited.

  A world with no entry (the Vale, homes, a world that only uses shared art, any world the build
  hasn't seen) needs nothing: the client just builds it from the base. The same is true when there is
  no manifest at all (a dev server with no web export, or a `--monolithic` build).

  The manifest never changes while a release runs (it is baked into the image), so it's read once and
  kept in `:persistent_term`. A missing manifest is NOT cached, so a dev server picks up an export
  made after it started.
  """

  @key {__MODULE__, :manifest}

  @type descriptor :: %{
          id: String.t(),
          url: String.t(),
          bytes: non_neg_integer(),
          sha256: String.t(),
          probe: String.t()
        }

  @doc """
  The packs a world needs, as the descriptors the client downloads (`[]` if none). `slug` may be nil
  (a home world has no catalog slug).
  """
  @spec for_world(String.t() | nil) :: [descriptor()]
  def for_world(slug) when is_binary(slug), do: descriptors(manifest(), slug)
  def for_world(_), do: []

  @doc "The same lookup against an explicit manifest map. Pure, so it can be tested without a file."
  @spec descriptors(map(), String.t()) :: [descriptor()]
  def descriptors(manifest, slug) when is_map(manifest) and is_binary(slug) do
    packs = Map.get(manifest, "packs", %{})

    manifest
    |> Map.get("worlds", %{})
    |> Map.get(slug, [])
    |> Enum.flat_map(fn id ->
      case Map.get(packs, id) do
        %{"url" => url, "bytes" => bytes, "sha256" => sha, "probe" => probe} ->
          [%{id: id, url: url, bytes: bytes, sha256: sha, probe: probe}]

        _ ->
          # A world naming a pack the manifest doesn't have: skip it rather than crash a join. The
          # build verifies worlds against their packs, so this only happens with a hand-edited manifest.
          []
      end
    end)
  end

  @doc "Where the build writes the manifest (overridable in config for tests)."
  @spec manifest_path() :: Path.t()
  def manifest_path do
    Application.get_env(:server, :packs_manifest_path) ||
      Application.app_dir(:server, "priv/static/packs/manifest.json")
  end

  @doc "Forget the cached manifest (tests, and a hot reload after a new export)."
  @spec reload() :: :ok
  def reload do
    _ = :persistent_term.erase(@key)
    :ok
  end

  defp manifest do
    case :persistent_term.get(@key, nil) do
      nil -> load()
      manifest -> manifest
    end
  end

  defp load do
    with {:ok, body} <- File.read(manifest_path()),
         {:ok, %{} = manifest} <- Jason.decode(body) do
      :persistent_term.put(@key, manifest)
      manifest
    else
      _ -> %{}
    end
  end
end
