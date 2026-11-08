defmodule Server.HowlTest do
  use ExUnit.Case, async: true

  alias Server.Howl

  test "only a world with an echo secret relays howls" do
    echo = %{spec: %{"core" => %{"secret" => %{"reveal" => %{"type" => "echo"}}}}}
    other = %{spec: %{"core" => %{"secret" => %{"reveal" => %{"type" => "listen"}}}}}
    none = %{spec: %{"core" => %{}}}
    assert Howl.echo_world?(echo)
    refute Howl.echo_world?(other)
    refute Howl.echo_world?(none)
  end

  test "a player may howl once per gap" do
    assert Howl.allow?(nil, 1_000)
    refute Howl.allow?(1_000, 1_500)
    assert Howl.allow?(1_000, 2_300)
  end

  test "the payload is the server's own position, or nothing" do
    assert Howl.payload([10.0, -4.5]) == %{x: 10.0, y: -4.5}
    assert Howl.payload(nil) == nil
  end
end
