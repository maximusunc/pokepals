defmodule Server.Router do
  @moduledoc """
  The non-socket HTTP surface, plugged as the endpoint's fallback after the `/ws` socket:

    * `GET /health`        — liveness.
    * `GET /worlds`        — the public world catalog (paginated; `?limit=&offset=&display_type=`).
    * `GET /worlds/:id`    — one world's spec by `world_id` (UUID) or `slug`.
    * `GET /worlds/:id/packs` — the downloadable art packs that world needs beyond the base web client
      (`Server.Packs`). The client asks this BEFORE joining the world, fetches what it is missing, and
      only then joins, so a world is never built (or its first messages handled) half-dressed.
    * `POST /session`      — trade a device token (`Authorization: Bearer ...`) for a 60-second socket
      ticket (issue 175). The socket only takes tickets, so the long-lived token never rides in a URL.
    * `POST /link/redeem`  — a NEW device offers a "Link a device" code and its own fresh token, and
      polls until the owner answers (Server.Links).

  The world endpoints are read-only and CDN-friendly (cache by the spec's `version`) — DEFERRED SEAM:
  front them with a CDN / move spec bodies to object storage when the catalog grows. The Godot client
  currently gets a world's spec over the channel on join (so a visit is one round-trip); these HTTP
  routes exist for tooling, a future world browser, and the CDN path.
  """
  use Plug.Router

  plug :match

  # JSON bodies for the two POSTs. Small: nothing we accept is more than a code, a token and a name.
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    json_decoder: Jason,
    length: 4_096

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

  post "/session" do
    # Named on first sight; renamed whenever the device sends a name again.
    name = Server.Devices.clean_name(conn.body_params["device_name"])

    with {:ok, token} <- bearer_token(conn),
         {:ok, _account, device} <- Server.Accounts.resolve_device(token, name) do
      device = Server.Devices.touch(device, name)

      json(conn, 200, %{
        ticket: Server.UserSocket.mint_ticket(device.device_id),
        expires_in: Server.UserSocket.ticket_max_age()
      })
    else
      :bad_request -> json(conn, 400, %{error: "bad_request"})
      {:error, :revoked} -> json(conn, 401, %{error: "revoked"})
      {:error, _} -> json(conn, 503, %{error: "unavailable"})
    end
  end

  post "/link/redeem" do
    p = conn.body_params

    case Server.Links.redeem(p["code"], p["token"], p["device_name"], conn.remote_ip) do
      :pending -> json(conn, 202, %{status: "pending"})
      :linked -> json(conn, 200, %{status: "linked"})
      :denied -> json(conn, 403, %{error: "denied"})
      :invalid -> json(conn, 404, %{error: "invalid"})
      :slow_down -> json(conn, 429, %{error: "slow_down"})
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  # --- helpers ---

  # The device token from `Authorization: Bearer <token>`; anything missing or blank is a bad request.
  defp bearer_token(conn) do
    with [header | _] <- get_req_header(conn, "authorization"),
         [scheme, token] <- String.split(header, " ", parts: 2),
         "bearer" <- String.downcase(scheme),
         token when token != "" <- String.trim(token) do
      {:ok, token}
    else
      _ -> :bad_request
    end
  end

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
