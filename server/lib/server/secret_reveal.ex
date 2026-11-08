defmodule Server.SecretReveal do
  @moduledoc """
  How a world's secret becomes findable (docs/home-world-and-secrets-design.md, W-1..W-5): the
  `reveal` block of its `secret`. The client stages the moment; the server checks what it can before
  honouring a claim, alongside `Server.Discoveries.claimable?/3`'s "this world, standing at it".

    * `always` (the default): it's simply there to be found (the Maze's seed, the Bazaar's river-drop).
    * `ward_open`: it can only be taken once a Ruin ward (`ward`) is open, the shared,
      server-authoritative door state (the Ruin's lantern, lit once the great door opens).
    * `hunt_perfect`: it only appears after a hunt that found every salamander in one go, which this
      player's channel remembers from its `hunt_complete` (the Riverbank's elder).
    * `stillness`: it appears after keeping still by a place for a while (Nocthollow's mere-pearl).
      Stillness happens entirely on the player's own screen, so the server only checks "this world,
      standing at it" for it.
    * `touch_all`: it appears once this player has touched every one of the reveal's `props` (flare
      props) in one visit, which the channel remembers from the `flare`s it relayed (Bobbledown's seven
      chime-bubbles, which bring up the Burbler's first breath).

    * `tracks`: it appears once the player's fox has led them along the snow-hare's trail to its den
      (Drifthallow's frost-flower). The trail, the fox's nose and the waiting all happen on the player's
      own screen (`TrailGuide` on the client), so the server only checks "this world, standing at it",
      like `stillness`. Honest about what that means: it can't tell a walked trail from a walked-to den.

    * `listen`: it is simply there to be found, but only the player's companion can hear where
      (Steamhollow's faint bell, in the fog). The listening (calm, settled beside you, the gaze turning
      toward the sound) happens entirely on the player's own screen (`ListenGuide` on the client), so
      the server only checks "this world, standing at it", like `stillness` and `tracks`. Honest about
      what that means: it can't tell a heard bell from a stumbled-on one.

  Pure: the channel hands in what it knows as `ctx` (`wards`: the world's ward list; `hunt_found`:
  the best count this visit's hunts reported; `hunt_goal`: the world's hunt goal; `touched`: the set
  of flare props this player has touched this visit).
  """

  @doc "Whether `secret`'s reveal condition is met, given what the channel knows."
  @spec met?(map(), map()) :: boolean()
  def met?(secret, ctx) when is_map(secret) do
    case Map.get(secret, "reveal", %{}) do
      %{"type" => "ward_open", "ward" => ward} -> ward_open?(Map.get(ctx, :wards, []), ward)
      %{"type" => "hunt_perfect"} -> hunt_perfect?(Map.get(ctx, :hunt_found, 0), Map.get(ctx, :hunt_goal, %{}))
      %{"type" => "touch_all", "props" => props} -> touched_all?(Map.get(ctx, :touched, MapSet.new()), props)
      %{"type" => type} when type in ["always", "stillness", "tracks", "listen"] -> true
      %{} = reveal when map_size(reveal) == 0 -> true
      _ -> false
    end
  end

  def met?(_secret, _ctx), do: false

  defp ward_open?(wards, ward) do
    Enum.any?(wards, fn w -> to_string(Map.get(w, :id, Map.get(w, "id"))) == ward and Map.get(w, :open, Map.get(w, "open")) == true end)
  end

  defp touched_all?(touched, props) when is_list(props) and props != [] do
    Enum.all?(props, &MapSet.member?(touched, &1))
  end

  defp touched_all?(_touched, _props), do: false

  defp hunt_perfect?(found, goal) do
    count = Map.get(goal, "count", 0)
    is_integer(found) and is_integer(count) and count > 0 and found >= count
  end
end
