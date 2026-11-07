defmodule Server.Router do
  @moduledoc """
  The non-socket HTTP surface, plugged as the endpoint's fallback after the `/ws` socket:

    * `GET /health`        — liveness.
    * `GET /worlds`        — the public world catalog (paginated; `?limit=&offset=&display_type=`).
    * `GET /worlds/:id`    — one world's spec by `world_id` (UUID) or `slug`.
    * `GET /worlds/:id/packs` — the downloadable art packs that world needs beyond the base web client
      (`Server.Packs`). The client asks this BEFORE joining the world, fetches what it is missing, and
      only then joins, so a world is never built (or its first messages handled) half-dressed.

  The world endpoints are read-only and CDN-friendly (cache by the spec's `version`) — DEFERRED SEAM:
  front them with a CDN / move spec bodies to object storage when the catalog grows. The Godot client
  currently gets a world's spec over the channel on join (so a visit is one round-trip); these HTTP
  routes exist for tooling, a future world browser, and the CDN path.
  """
  use Plug.Router

  plug :match
  plug :dispatch

  # The web client's entry point. `Plug.Static` (in the endpoint) serves the export's named assets,
  # but a bare `GET /` has no filename to match, so we resolve it to `index.html` here. Until the
  # Godot "Web" preset has been exported into `priv/static`, we say so plainly instead of 404-ing.
  get "/" do
    index = Application.app_dir(:server, "priv/static/index.html")

    if File.exists?(index) do
      conn
      |> put_resp_content_type("text/html")
      |> send_file(200, index)
    else
      send_resp(
        conn,
        503,
        "Web client not built yet. Export Godot's 'Web' preset into server/priv/static/ " <>
          "(see docs/web-export.md)."
      )
    end
  end

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  get "/worlds" do
    conn = fetch_query_params(conn)
    opts = catalog_opts(conn.query_params)

    worlds = Enum.map(Server.Worlds.list(opts), &Server.Worlds.client_view/1)
    json(conn, 200, %{worlds: worlds})
  end

  get "/worlds/:id" do
    case Server.Worlds.get(id) || Server.Worlds.get_by_slug(id) do
      nil -> json(conn, 404, %{error: "not_found"})
      world -> json(conn, 200, Server.Worlds.client_view(world))
    end
  end

  get "/worlds/:id/packs" do
    case find_world(id) do
      nil ->
        json(conn, 404, %{error: "not_found"})

      world ->
        json(conn, 200, %{
          world_id: world.world_id,
          name: world.name,
          packs: Server.Packs.for_world(world.slug)
        })
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  # --- helpers ---

  # A world by UUID or by slug. (Only a well-formed UUID may go to `Repo.get`, which raises on anything
  # else; a slug like "nocthollow" is looked up by slug instead.)
  defp find_world(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Server.Worlds.get(uuid) || Server.Worlds.get_by_slug(id)
      :error -> Server.Worlds.get_by_slug(id)
    end
  end

  defp catalog_opts(params) do
    []
    |> maybe_int(params, "limit", :limit)
    |> maybe_int(params, "offset", :offset)
    |> maybe_str(params, "display_type", :display_type)
  end

  defp maybe_int(opts, params, param, key) do
    case params[param] && Integer.parse(params[param]) do
      {n, _} -> [{key, n} | opts]
      _ -> opts
    end
  end

  defp maybe_str(opts, params, param, key) do
    case params[param] do
      nil -> opts
      val -> [{key, val} | opts]
    end
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
