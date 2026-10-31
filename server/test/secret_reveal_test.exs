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

  test "an unknown reveal type is never met" do
    refute SecretReveal.met?(%{"reveal" => %{"type" => "made_up"}}, %{})
  end
end
