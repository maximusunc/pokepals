defmodule Server.SessionWireTest do
  @moduledoc """
  "Newest device wins" and "sign out", on a REAL WebSocket (Bandit on a loopback port, a tiny raw
  client below): the old client must receive its `superseded` / `signed_out` frame BEFORE the socket
  closes, and the new socket must live on. The in-process ChannelTest can't show that ordering, since
  there the "socket" is the test process.
  """
  use Server.ChannelCase, async: false
  alias Server.{Accounts, Devices, UserSocket, Worlds}

  setup do
    {:ok, pid} =
      Bandit.start_link(plug: Server.Endpoint, ip: :loopback, port: 0, startup_log: false)

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    on_exit(fn -> Process.exit(pid, :normal) end)

    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: "wire-#{System.unique_integer([:positive])}",
        name: "Wire",
        display_types: ["2d"],
        version: 1,
        spec: %{"core" => %{}, "profiles" => %{"2d" => %{}}}
      })

    {:ok, account, device} = Accounts.resolve_device("wire-#{System.unique_integer([:positive])}")
    %{port: port, world: world_id, account: account, device: device}
  end

  test "a second device's connect tells the first `superseded` before closing it", ctx do
    {:ok, other} =
      Devices.add(
        ctx.account.user_id,
        Devices.hash_token("wire-b-#{System.unique_integer()}"),
        "B"
      )

    a = ws_connect(ctx.port, UserSocket.mint_ticket(ctx.device.device_id))
    assert ws_join(a, ctx.world) == "ok"

    b = ws_connect(ctx.port, UserSocket.mint_ticket(other.device_id))
    events = read_until_closed(a)
    assert "superseded" in events
    assert List.last(events) == :closed

    # The new socket is untouched and can play.
    assert ws_join(b, ctx.world) == "ok"
    ws_close(b)
  end

  test "signing a device out tells it `signed_out` before closing it", ctx do
    {:ok, other} =
      Devices.add(
        ctx.account.user_id,
        Devices.hash_token("wire-c-#{System.unique_integer()}"),
        "C"
      )

    a = ws_connect(ctx.port, UserSocket.mint_ticket(other.device_id))
    assert ws_join(a, ctx.world) == "ok"

    :ok = Devices.revoke(ctx.account.user_id, ctx.device.device_id, other.device_id)
    events = read_until_closed(a)
    assert "signed_out" in events
    assert List.last(events) == :closed
    # The closing channel may still be answering the "devices changed" note; let it finish.
    Process.sleep(100)
  end

  test "a socket that is only connected (no world yet) is told when it next joins", ctx do
    a = ws_connect(ctx.port, UserSocket.mint_ticket(ctx.device.device_id))
    b = ws_connect(ctx.port, UserSocket.mint_ticket(ctx.device.device_id))

    send_frame(a, ["1", "1", "world:" <> ctx.world, "phx_join", %{}])
    events = read_until_closed(a)
    assert "superseded" in events
    assert List.last(events) == :closed
    ws_close(b)
  end

  test "the socket refuses a bare token and a bad ticket", ctx do
    assert {:error, 403} = ws_try(ctx.port, "ticket=nope")
    assert {:error, 403} = ws_try(ctx.port, "")
  end

  # ── a tiny WebSocket client ──

  # Let a live socket's channel finish what it's doing (the join's pushes hit the database), then close
  # it and wait for the server side to go, so nothing outlives the test's database sandbox.
  defp ws_close(sock) do
    drain(sock)
    :gen_tcp.close(sock)
    Process.sleep(50)
  end

  defp drain(sock) do
    Process.delete({:buf, sock})

    case :gen_tcp.recv(sock, 0, 300) do
      {:ok, _} -> drain(sock)
      _ -> :ok
    end
  end

  defp ws_connect(port, ticket) do
    {:ok, sock} = ws_try(port, "ticket=" <> URI.encode_www_form(ticket))
    sock
  end

  defp ws_try(port, query) do
    {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw])

    :ok =
      :gen_tcp.send(sock, [
        "GET /ws/websocket?vsn=2.0.0&#{query} HTTP/1.1\r\n",
        "Host: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n",
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
      ])

    {status, rest} = read_head(sock, "")

    case status do
      101 ->
        Process.put({:buf, sock}, rest)
        {:ok, sock}

      other ->
        :gen_tcp.close(sock)
        {:error, other}
    end
  end

  defp read_head(sock, acc) do
    case :binary.split(acc, "\r\n\r\n") do
      [head, rest] ->
        ["HTTP/1.1 " <> code | _] = String.split(head, "\r\n")
        {code |> String.slice(0, 3) |> String.to_integer(), rest}

      [_] ->
        {:ok, more} = :gen_tcp.recv(sock, 0, 5_000)
        read_head(sock, acc <> more)
    end
  end

  defp ws_join(sock, world) do
    send_frame(sock, ["1", "1", "world:" <> world, "phx_join", %{}])
    wait_reply(sock)
  end

  defp wait_reply(sock) do
    case read_frame(sock) do
      {:text, [_, "1", _, "phx_reply", %{"status" => status}]} -> status
      {:text, _} -> wait_reply(sock)
      other -> flunk("no join reply: #{inspect(other)}")
    end
  end

  # Every event the server sends, in order, ending with :closed (a close frame or the connection
  # going), or :timeout if the server just went quiet.
  defp read_until_closed(sock, acc \\ []) do
    case read_frame(sock) do
      {:text, [_, _, _, event, _]} -> read_until_closed(sock, [event | acc])
      {:text, _} -> read_until_closed(sock, acc)
      :timeout -> Enum.reverse([:timeout | acc])
      _closed -> Enum.reverse([:closed | acc])
    end
  end

  defp send_frame(sock, msg) do
    payload = Jason.encode!(msg)
    mask = :crypto.strong_rand_bytes(4)
    len = byte_size(payload)

    header =
      cond do
        len < 126 -> <<1::1, 0::3, 1::4, 1::1, len::7>>
        true -> <<1::1, 0::3, 1::4, 1::1, 126::7, len::16>>
      end

    :ok = :gen_tcp.send(sock, [header, mask, mask_bytes(payload, mask)])
  end

  defp mask_bytes(payload, <<m::binary-size(4)>>) do
    payload
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.map(fn {b, i} -> Bitwise.bxor(b, :binary.at(m, rem(i, 4))) end)
    |> :binary.list_to_bin()
  end

  defp read_frame(sock) do
    with {:ok, <<_fin::1, _::3, opcode::4, _mask::1, len7::7>>} <- take(sock, 2),
         {:ok, len} <- ext_len(sock, len7),
         {:ok, payload} <- take(sock, len) do
      case opcode do
        1 -> {:text, Jason.decode!(payload)}
        8 -> :close
        _ -> read_frame(sock)
      end
    else
      {:error, :timeout} -> :timeout
      _ -> :closed
    end
  end

  defp ext_len(sock, 126), do: with({:ok, <<n::16>>} <- take(sock, 2), do: {:ok, n})
  defp ext_len(sock, 127), do: with({:ok, <<n::64>>} <- take(sock, 8), do: {:ok, n})
  defp ext_len(_sock, n), do: {:ok, n}

  defp take(_sock, 0), do: {:ok, ""}

  defp take(sock, n) do
    buf = Process.get({:buf, sock}, "")

    if byte_size(buf) >= n do
      <<out::binary-size(n), rest::binary>> = buf
      Process.put({:buf, sock}, rest)
      {:ok, out}
    else
      case :gen_tcp.recv(sock, 0, 5_000) do
        {:ok, more} ->
          Process.put({:buf, sock}, buf <> more)
          take(sock, n)

        error ->
          error
      end
    end
  end
end
