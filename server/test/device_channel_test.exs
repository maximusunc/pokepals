defmodule Server.DeviceChannelTest do
  @moduledoc """
  Issue 175 over the channel: socket tickets, "Link a device" (link_code -> redeem -> link_request ->
  link_answer), the device list, signing a device out, and the newest connection winning.
  """
  use Server.ChannelCase, async: false
  alias Phoenix.Socket.Broadcast
  alias Server.{Accounts, Devices, Links, LinkThrottle, UserSocket, Worlds}

  setup do
    LinkThrottle.reset()
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: "dev-#{System.unique_integer([:positive])}",
        name: "Devices",
        display_types: ["2d"],
        version: 1,
        spec: %{"core" => %{}, "profiles" => %{"2d" => %{}}}
      })

    token = "devc-#{System.unique_integer([:positive])}"
    {:ok, account, device} = Accounts.resolve_device(token, "Phone")
    %{world: world_id, token: token, uid: account.user_id, device: device}
  end

  defp enter(socket, world) do
    {:ok, _reply, socket} = subscribe_and_join(socket, "world:" <> world, %{})
    assert_push "load", %{}
    socket
  end

  describe "tickets" do
    test "a fresh ticket connects as its device", ctx do
      {:ok, socket} = connect(UserSocket, %{"ticket" => UserSocket.mint_ticket(ctx.device.device_id)})
      assert socket.assigns.user_id == ctx.uid
      assert socket.assigns.device_id == ctx.device.device_id
    end

    test "an old, forged or signed-out device's ticket is refused", ctx do
      old =
        Phoenix.Token.sign(Server.Endpoint, "socket ticket", ctx.device.device_id,
          signed_at: System.system_time(:second) - 120
        )

      assert connect(UserSocket, %{"ticket" => old}) == :error
      assert connect(UserSocket, %{"ticket" => "forged"}) == :error
      assert connect(UserSocket, %{}) == :error

      {:ok, other} = Devices.add(ctx.uid, Devices.hash_token("devc-other-#{System.unique_integer()}"), "Other")
      ticket = UserSocket.mint_ticket(other.device_id)
      :ok = Devices.revoke(ctx.uid, ctx.device.device_id, other.device_id)
      assert connect(UserSocket, %{"ticket" => ticket}) == :error
    end
  end

  describe "link a device" do
    test "link_code -> redeem -> link_request -> allow -> the list grows", ctx do
      {:ok, socket} = connect(UserSocket, %{"token" => ctx.token})
      socket = enter(socket, ctx.world)

      push(socket, "link_code", %{})
      assert_push "link_code", %{code: code, expires_in: 600}

      new_token = "devc-new-#{System.unique_integer([:positive])}"
      assert Links.redeem(code, new_token, "Tablet", {127, 0, 0, 1}) == :pending
      assert_push "link_request", %{device_name: "Tablet"}

      push(socket, "link_answer", %{"allow" => true})
      assert_push "devices", %{devices: [%{current: true, name: "Phone"}, %{current: false, name: "Tablet"}]}
      assert Links.redeem(code, new_token, "Tablet", {127, 0, 0, 1}) == :linked
    end

    test "nothing waiting, or a full account, says link_failed", ctx do
      {:ok, socket} = connect(UserSocket, %{"token" => ctx.token})
      socket = enter(socket, ctx.world)

      push(socket, "link_answer", %{"allow" => true})
      assert_push "link_failed", %{reason: "expired"}

      for _ <- 2..10, do: {:ok, _} = Devices.add(ctx.uid, Devices.hash_token("f-#{System.unique_integer()}"), "More")
      code = Links.new_code(ctx.uid)
      assert Links.redeem(code, "devc-full-#{System.unique_integer()}", "x", {127, 0, 0, 1}) == :pending
      assert_push "link_request", %{}
      push(socket, "link_answer", %{"allow" => true})
      assert_push "link_failed", %{reason: "too_many"}
    end
  end

  describe "devices" do
    test "the list, and signing another device out", ctx do
      {:ok, other} = Devices.add(ctx.uid, Devices.hash_token("devc-o-#{System.unique_integer()}"), "Laptop")
      {:ok, socket} = connect(UserSocket, %{"token" => ctx.token})
      socket = enter(socket, ctx.world)

      push(socket, "devices", %{})
      assert_push "devices", %{devices: [%{current: true, id: id}, %{name: "Laptop", current: false}]}
      assert id == ctx.device.device_id

      # This device can't sign itself out: the list comes back unchanged.
      push(socket, "device_revoke", %{"id" => ctx.device.device_id})
      assert_push "devices", %{devices: [_, _]}

      push(socket, "device_revoke", %{"id" => other.device_id})
      assert_push "devices", %{devices: [%{current: true}]}
      assert Devices.get_active(other.device_id) == nil
    end

    test "the signed-out device's live socket is told signed_out, then dropped", ctx do
      {:ok, other} = Devices.add(ctx.uid, Devices.hash_token("devc-s-#{System.unique_integer()}"), "Laptop")
      {:ok, socket} = connect(UserSocket, %{"ticket" => UserSocket.mint_ticket(other.device_id)})
      _socket = enter(socket, ctx.world)

      :ok = Devices.revoke(ctx.uid, ctx.device.device_id, other.device_id)
      assert_push "signed_out", %{}
      assert_receive %Broadcast{event: "disconnect"}
    end
  end

  describe "newest connection wins" do
    test "a second connect tells the first superseded and drops it; the new one plays on", ctx do
      {:ok, first} = connect(UserSocket, %{"token" => ctx.token})
      _first = enter(first, ctx.world)

      {:ok, second} = connect(UserSocket, %{"token" => ctx.token})
      assert_push "superseded", %{}
      assert_receive %Broadcast{event: "disconnect"}

      _second = enter(second, ctx.world)
      refute_push "superseded", %{}
    end

    test "a socket with no world open is told when it next joins", ctx do
      {:ok, stale} = connect(UserSocket, %{"token" => ctx.token})
      {:ok, _newer} = connect(UserSocket, %{"token" => ctx.token})

      {:ok, _reply, _} = subscribe_and_join(stale, "world:" <> ctx.world, %{})
      assert_push "superseded", %{}
      assert_receive %Broadcast{event: "disconnect"}
      refute_push "load", %{}
    end
  end
end
