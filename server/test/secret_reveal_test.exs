defmodule Server.SecretRevealTest do
  use ExUnit.Case, async: true
  alias Server.SecretReveal

  test "a secret with no reveal, or 'always', is simply there" do
    assert SecretReveal.met?(%{"id" => "seed"}, %{})
    assert SecretReveal.met?(%{"reveal" => %{"type" => "always"}}, %{})
  end

  test "stillness is staged on the player's screen, so the server doesn't gate it" do
    assert SecretReveal.met?(%{"reveal" => %{"type" => "stillness", "seconds" => 20}}, %{})
  end

  test "tracks are followed on the player's screen too, so the server doesn't gate them" do
    secret = %{"reveal" => %{"type" => "tracks", "start" => [0, 0], "trail" => [[10, 0], [20, 0]]}}
    assert SecretReveal.met?(secret, %{})
  end

  test "a dream is napped, dreamed and walked to on the player's screen, so the server doesn't gate it" do
    secret = %{"reveal" => %{"type" => "dream", "landmark" => "crooked_arch", "spots" => [[0, 0]], "landmark_position" => [100, 100]}}
    assert SecretReveal.met?(secret, %{})
  end

  test "the faint bell is listened for on the player's screen, so the server doesn't gate it" do
    secret = %{"reveal" => %{"type" => "listen", "hear_range_low" => 320.0, "settle_low" => 2.4}}
    assert SecretReveal.met?(secret, %{})
  end

  test "the answering stone's cave opens on the player's screen, so the server doesn't gate it" do
    secret = %{"reveal" => %{"type" => "echo", "walls" => [[0, 0, 10, 0]], "cave" => %{"mouth" => [5, 5]}}}
    assert SecretReveal.met?(secret, %{})
  end

  test "the root-heart is followed to on the player's screen, so the server doesn't gate it" do
    secret = %{"reveal" => %{"type" => "follow", "reach_low" => 2600.0, "arrive_player" => 130.0}}
    assert SecretReveal.met?(secret, %{})
  end

  test "the paper bird behind the mural's door is earned on the player's screen, so the server doesn't gate it" do
    secret = %{"reveal" => %{"type" => "shadow", "species" => "bird", "spot" => [40, 111]}}
    assert SecretReveal.met?(secret, %{})
  end

  test "the mirror stone is walked to behind a reflection on the player's screen, so the server doesn't gate it" do
    secret = %{"reveal" => %{"type" => "reflection", "start" => [0, 0], "trail" => [[10, 0], [20, 0]], "pace" => 68.0}}
    assert SecretReveal.met?(secret, %{})
  end

  describe "the sand-dollar only rises at the lowest tide (the server checks the clock)" do
    @tide %{"period_s" => 360.0, "epoch_s" => 0.0, "level_low" => 0.30, "level_high" => 0.78, "yield_level" => 0.345}
    @secret %{"reveal" => %{"type" => "tide", "tide" => @tide, "grace_s" => 30.0}}
    # the lowest point of the tide is half a period in; the window is about +-35.7 s round it
    @lowest 180_000

    test "a claim in the middle of the lowest water is honoured" do
      assert SecretReveal.met?(@secret, %{now_ms: @lowest})
      assert SecretReveal.met?(@secret, %{now_ms: @lowest + 30_000})
    end

    test "a claim at high water, or on the way out, is not" do
      refute SecretReveal.met?(@secret, %{now_ms: 0})
      refute SecretReveal.met?(@secret, %{now_ms: 90_000})
      refute SecretReveal.met?(@secret, %{now_ms: 270_000})
    end

    test "a slow claim is still honoured for the grace period after the window closes, and not after" do
      # window edge ~35.66 s from the lowest; grace 30 s
      assert SecretReveal.met?(@secret, %{now_ms: @lowest + 60_000})
      refute SecretReveal.met?(@secret, %{now_ms: @lowest + 70_000})
      refute SecretReveal.met?(@secret, %{now_ms: @lowest - 70_000})
    end

    test "every later tide has its own window" do
      assert SecretReveal.met?(@secret, %{now_ms: @lowest + 360_000 * 7})
      refute SecretReveal.met?(@secret, %{now_ms: 360_000 * 7})
    end

    test "with no clock (or a malformed reveal) it refuses rather than guessing" do
      refute SecretReveal.met?(@secret, %{})
      refute SecretReveal.met?(@secret, %{now_ms: nil})
      refute SecretReveal.met?(%{"reveal" => %{"type" => "tide"}}, %{now_ms: @lowest})
    end

    test "no grace means exactly the window" do
      strict = put_in(@secret, ["reveal", "grace_s"], 0.0)
      assert SecretReveal.met?(strict, %{now_ms: @lowest + 35_000})
      refute SecretReveal.met?(strict, %{now_ms: @lowest + 36_500})
    end
  end

  test "a lantern behind a ward can only be taken once that ward is open" do
    secret = %{"reveal" => %{"type" => "ward_open", "ward" => "paired_hall"}}
    refute SecretReveal.met?(secret, %{wards: []})
    refute SecretReveal.met?(secret, %{wards: [%{id: "paired_hall", open: false, plates: %{}}]})
    refute SecretReveal.met?(secret, %{wards: [%{id: "cistern_light", found: true, open: true}]})
    assert SecretReveal.met?(secret, %{wards: [%{id: "paired_hall", open: true, plates: %{}}]})
  end

  test "the elder only shows after a hunt that found them all" do
    secret = %{"reveal" => %{"type" => "hunt_perfect"}}
    goal = %{"type" => "find_salamanders", "count" => 10}
    refute SecretReveal.met?(secret, %{hunt_found: 9, hunt_goal: goal})
    refute SecretReveal.met?(secret, %{hunt_found: 10, hunt_goal: %{}})
    assert SecretReveal.met?(secret, %{hunt_found: 10, hunt_goal: goal})
  end

  test "the first bubble only rises once every chime-bubble has been rung this visit" do
    secret = %{"reveal" => %{"type" => "touch_all", "props" => ["chime_a", "chime_b", "chime_c"]}}
    refute SecretReveal.met?(secret, %{})
    refute SecretReveal.met?(secret, %{touched: MapSet.new(["chime_a", "chime_b"])})
    assert SecretReveal.met?(secret, %{touched: MapSet.new(["chime_a", "chime_b", "chime_c", "a_bloom"])})
    refute SecretReveal.met?(%{"reveal" => %{"type" => "touch_all", "props" => []}}, %{touched: MapSet.new()})
  end

  test "an unknown reveal type is never met" do
    refute SecretReveal.met?(%{"reveal" => %{"type" => "made_up"}}, %{})
  end
end
