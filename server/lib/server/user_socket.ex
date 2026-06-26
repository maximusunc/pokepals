defmodule Server.UserSocket do
  @moduledoc """
  The socket-level session. Authentication happens once, here, in `connect/3`: the client passes its
  anonymous bearer `token` (a connect param), which we resolve to the internal `user_id` and stash in
  the socket assigns. Every channel the client joins inherits that `user_id` — gameplay never sees
  the token again. An unknown token mints a fresh account (a brand-new player just plays); only a
  missing/blank token is rejected.
  """
  use Phoenix.Socket

  # One channel topic per world: "world:" <> world_id (multi-world routing).
  channel "world:*", Server.WorldChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) and token != "" do
    case Server.Accounts.resolve_token(token) do
      {:ok, account} -> {:ok, assign(socket, :user_id, account.user_id)}
      {:error, _} -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  # Lets the server address all of a player's live sockets (e.g. a future forced disconnect on ban).
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
