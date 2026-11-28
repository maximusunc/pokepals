defmodule Server.UserSocket do
  @moduledoc """
  The socket-level session. Authentication happens once, here, in `connect/3`. The client first trades
  its long-lived device token for a short-lived TICKET over HTTPS (`POST /session`, Server.Router), then
  opens the socket with `?ticket=...`. The ticket is a `Phoenix.Token` carrying the device id, good
  for 60 seconds, so the long-lived token never sits in a WebSocket URL (where proxies and logs keep
  URLs). We load the device (refusing a signed-out one) and stash `user_id` and `device_id` in the
  socket assigns; every channel the client joins inherits them, and gameplay never sees a credential.

  Connecting also makes this the player's ONE live session (Server.Sessions): any older socket of
  theirs is told `superseded` and dropped.

  Tests may still connect with `token` (a compile-time switch only config/test.exs turns on), so the
  hundreds of channel tests don't each need an HTTP round trip first.
  """
  use Phoenix.Socket
  alias Server.{Devices, Sessions}

  # One channel topic per world: "world:" <> world_id (multi-world routing).
  channel "world:*", Server.WorldChannel

  @ticket_salt "socket ticket"
  @ticket_max_age 60

  @allow_token_param Application.compile_env(:server, [__MODULE__, :allow_token_param], false)

  @doc "A fresh socket ticket for a device: signed with the endpoint's secret, good for 60 seconds."
  @spec mint_ticket(Ecto.UUID.t()) :: String.t()
  def mint_ticket(device_id), do: Phoenix.Token.sign(Server.Endpoint, @ticket_salt, device_id)

  @doc "How long a ticket is good for, in seconds."
  def ticket_max_age, do: @ticket_max_age

  @impl true
  def connect(%{"ticket" => ticket}, socket, _connect_info) when is_binary(ticket) and ticket != "" do
    with {:ok, device_id} <-
           Phoenix.Token.verify(Server.Endpoint, @ticket_salt, ticket, max_age: @ticket_max_age),
         %{} = device <- Devices.get_active(device_id) do
      {:ok, start_session(socket, device.user_id, device.device_id)}
    else
      _ -> :error
    end
  end

  if @allow_token_param do
    def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) and token != "" do
      case Server.Accounts.resolve_device(token) do
        {:ok, account, device} -> {:ok, start_session(socket, account.user_id, device.device_id)}
        {:error, _} -> :error
      end
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  defp start_session(socket, user_id, device_id) do
    gen = Sessions.begin(user_id)
    assign(socket, %{user_id: user_id, device_id: device_id, session_gen: gen})
  end

  # Lets the server address all of a player's live sockets (e.g. a future forced disconnect on ban).
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
