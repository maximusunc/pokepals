defmodule Server.RouterAuthTest do
  @moduledoc "POST /session (device token -> socket ticket) and POST /link/redeem, over the plug router."
  use Server.DataCase, async: false
  import Plug.Test
  import Plug.Conn
  alias Server.{Accounts, Devices, Links, LinkThrottle, Router}

  setup do
    LinkThrottle.reset()
    on_exit(&LinkThrottle.reset/0)
    :ok
  end

  defp post_json(path, body, headers \\ []) do
    conn =
      Enum.reduce(headers, conn(:post, path, Jason.encode!(body)), fn {k, v}, c -> put_req_header(c, k, v) end)
      |> put_req_header("content-type", "application/json")

    conn = Router.call(conn, Router.init([]))
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp session(token, body \\ %{}), do: post_json("/session", body, [{"authorization", "Bearer " <> token}])

  describe "POST /session" do
    test "a token gets a 60-second ticket for its device, minting the account on first sight" do
      token = "sess-#{System.unique_integer([:positive])}"
      assert {200, %{"ticket" => ticket, "expires_in" => 60}} = session(token, %{"device_name" => "Laptop"})

      device = Devices.by_token(token)
      assert device.name == "Laptop"
      assert device.last_seen_at
      assert {:ok, device_id} = Phoenix.Token.verify(Server.Endpoint, "socket ticket", ticket, max_age: 60)
      assert device_id == device.device_id
      refute String.contains?(ticket, token)
    end

    test "a name sent again renames the device; no name keeps it" do
      token = "sess-#{System.unique_integer([:positive])}"
      {200, _} = session(token, %{"device_name" => "Old"})
      {200, _} = session(token)
      assert Devices.by_token(token).name == "Old"
      {200, _} = session(token, %{"device_name" => "New"})
      assert Devices.by_token(token).name == "New"
    end

    test "a missing or blank token is a bad request" do
      assert {400, %{"error" => "bad_request"}} = post_json("/session", %{})
      assert {400, %{"error" => "bad_request"}} = session("   ")
      assert {400, %{"error" => "bad_request"}} = post_json("/session", %{}, [{"authorization", "Basic abc"}])
    end

    test "a signed-out device is told revoked" do
      token = "sess-gone-#{System.unique_integer([:positive])}"
      {:ok, account, device} = Accounts.resolve_device(token)
      {:ok, keeper} = Devices.add(account.user_id, Devices.hash_token("keeper-#{System.unique_integer()}"), "K")
      :ok = Devices.revoke(account.user_id, keeper.device_id, device.device_id)
      assert {401, %{"error" => "revoked"}} = session(token)
    end
  end

  describe "POST /link/redeem" do
    setup do
      {:ok, account} = Accounts.resolve_token("link-owner-#{System.unique_integer([:positive])}")
      %{uid: account.user_id, code: Links.new_code(account.user_id)}
    end

    defp redeem(body), do: post_json("/link/redeem", body)

    test "pending, polled, then linked once the owner allows", %{uid: uid, code: code} do
      body = %{"code" => code, "token" => "nd-#{System.unique_integer([:positive])}", "device_name" => "Tablet"}
      assert {202, %{"status" => "pending"}} = redeem(body)
      assert {202, %{"status" => "pending"}} = redeem(body)
      :ok = Links.answer(uid, true)
      assert {200, %{"status" => "linked"}} = redeem(body)
      assert {200, %{"status" => "linked"}} = redeem(body)

      # The new device's token now opens a session on the owner's account.
      assert {200, %{"ticket" => _}} = session(body["token"])
      assert Devices.by_token(body["token"]).user_id == uid
    end

    test "denied", %{uid: uid, code: code} do
      body = %{"code" => code, "token" => "nd-#{System.unique_integer([:positive])}"}
      assert {202, _} = redeem(body)
      :ok = Links.answer(uid, false)
      assert {403, %{"error" => "denied"}} = redeem(body)
    end

    test "unknown, malformed and expired codes are invalid", %{code: code} do
      assert {404, %{"error" => "invalid"}} = redeem(%{"code" => "ZZZZ-ZZZZ", "token" => "nd-1"})
      assert {404, %{"error" => "invalid"}} = redeem(%{"token" => "nd-2"})
      assert {404, %{"error" => "invalid"}} = redeem(%{"code" => code})

      Repo.update_all(Server.LinkCode, set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])
      assert {404, %{"error" => "invalid"}} = redeem(%{"code" => code, "token" => "nd-3"})
    end

    test "too many wrong codes is slow_down" do
      for n <- 1..10, do: assert({404, _} = redeem(%{"code" => "ZZZZ-ZZZZ", "token" => "nd-#{n}"}))
      assert {429, %{"error" => "slow_down"}} = redeem(%{"code" => "ZZZZ-ZZZZ", "token" => "nd-x"})
    end
  end
end
