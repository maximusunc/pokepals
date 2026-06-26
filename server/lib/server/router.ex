defmodule Server.Router do
  @moduledoc """
  The non-socket HTTP surface, plugged as the endpoint's fallback after the `/ws` socket:

    * `GET /health`        — liveness.
    * `GET /worlds`        — the public world catalog (paginated; `?limit=&offset=&display_type=`).
    * `GET /worlds/:id`    — one world's spec by `world_id` (UUID) or `slug`.

  The world endpoints are read-only and CDN-friendly (cache by the spec's `version`) — DEFERRED SEAM:
  front them with a CDN / move spec bodies to object storage when the catalog grows. The Godot client
  currently gets a world's spec over the channel on join (so a visit is one round-trip); these HTTP
  routes exist for tooling, a future world browser, and the CDN path.
  """
  use Plug.Router

  plug :match
  plug :dispatch

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

  match _ do
    send_resp(conn, 404, "not found")
  end

  # --- helpers ---

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
