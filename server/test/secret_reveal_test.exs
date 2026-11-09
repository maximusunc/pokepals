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

  test "the mirror stone is walked to behind a reflection on the player's screen, so the server doesn't gate it" do
    secret = %{"reveal" => %{"type" => "reflection", "start" => [0, 0], "trail" => [[10, 0], [20, 0]], "pace" => 68.0}}
    assert SecretReveal.met?(secret, %{})
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
