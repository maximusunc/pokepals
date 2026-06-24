defmodule Server.Repo do
  @moduledoc "The PostgreSQL repo. Library-style Ecto — no Phoenix Endpoint."
  use Ecto.Repo,
    otp_app: :server,
    adapter: Ecto.Adapters.Postgres
end
