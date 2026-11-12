defmodule Server.Fishing do
  @moduledoc """
  FISHING, the pilot usable item (docs/usable-items-design.md, U-3 to U-13): what a rod is, what can be
  caught, and the rules the channel judges a catch by. Pure data + pure functions; the channel
  (`Server.WorldChannel`) does the talking and `Server.Economy` does the granting.

  How a catch goes, server-authoritative from end to end:

    1. **Take the rod.** The starter rod rests on a post in the Vale (a spec prop with `"gives": "rod"`).
       Taking it is honoured only while you stand at that post, and only once: you get one rod, free.
    2. **Cast.** Honoured only if you own a rod and this world allows fishing (on by default; a world
       opts out with `"fishing": false` in its spec core, U-6/U-10). The server rolls WHAT is on the line
       right now (`roll/1`) and HOW LONG until it bites (`wait_ms/1`), keeps both to itself, and tells
       the client only the wait and the timing ring's difficulty, so the catch stays a surprise.
    3. **Reel.** The client plays the timing ring (U-4) and reports whether you tapped in time. The
       server grants the catch only for a reel that comes after the bite and before the ring could have
       run out (`reel_in_time?/3`), so a client can't skip the wait or reel a fish it never hooked.

  Every catch goes into your inventory (U-7): common fish to sell, rare fish for your home's tank,
  reeled-up materials to trade. No world-specific catches yet: every water uses the one default set
  (the first build's scope).
  """

  alias Server.{ItemDefinition, Repo}

  # The starter rod: a "tool" (a usable item that goes on the hotbar). `use` names what it does.
  @rod_id 10

  # What the water gives, rolled by `weight` (out of the total). `kind` is "fish" (common: sell it),
  # "rare_fish" (for the tank at home) or "material" (reeled-up things to trade, and later to craft with).
  # `ring` is the timing ring's difficulty (U-4): `window` is how wide the tap window is, as a share of
  # one pass of the ring, and `speed` how fast the ring closes (passes per 1.4 s). Rarer catches have a
  # smaller window and a quicker ring. `sell` is what the fish buyer will pay (step 2; not used yet).
  @catches [
    %{id: 200, key: "minnow", name: "Silver Minnow", kind: "fish", weight: 26, sell: 2,
      color: [0.78, 0.82, 0.86], ring: %{window: 0.24, speed: 0.9}},
    %{id: 201, key: "perch", name: "Speckled Perch", kind: "fish", weight: 20, sell: 3,
      color: [0.62, 0.70, 0.36], ring: %{window: 0.22, speed: 1.0}},
    %{id: 202, key: "loach", name: "Pebble Loach", kind: "fish", weight: 16, sell: 3,
      color: [0.62, 0.54, 0.44], ring: %{window: 0.22, speed: 1.0}},
    %{id: 203, key: "bream", name: "Reed Bream", kind: "fish", weight: 14, sell: 4,
      color: [0.80, 0.70, 0.44], ring: %{window: 0.20, speed: 1.05}},
    %{id: 204, key: "carp", name: "Mud Carp", kind: "fish", weight: 10, sell: 5,
      color: [0.56, 0.46, 0.30], ring: %{window: 0.18, speed: 1.1}},
    %{id: 220, key: "koi", name: "Moonscale Koi", kind: "rare_fish", weight: 2.5, sell: nil,
      color: [0.96, 0.94, 0.88], ring: %{window: 0.12, speed: 1.3}},
    %{id: 221, key: "ember_trout", name: "Ember Trout", kind: "rare_fish", weight: 1.5, sell: nil,
      color: [0.94, 0.48, 0.28], ring: %{window: 0.11, speed: 1.35}},
    %{id: 222, key: "old_whiskers", name: "Old Whiskers", kind: "rare_fish", weight: 1.0, sell: nil,
      color: [0.36, 0.40, 0.34], ring: %{window: 0.10, speed: 1.4}},
    %{id: 240, key: "old_boot", name: "Old Boot", kind: "material", weight: 6, sell: 1,
      color: [0.42, 0.30, 0.22], ring: %{window: 0.26, speed: 0.85}},
    %{id: 241, key: "sea_glass", name: "Sea-glass", kind: "material", weight: 3, sell: 4,
      color: [0.52, 0.80, 0.74], ring: %{window: 0.22, speed: 1.0}}
  ]

  # How long until a bite, from the cast (ms): a calm little wait, never the same twice.
  @wait_min_ms 1_800
  @wait_max_ms 5_200

  # The reel must come no sooner than this before the bite is due (network jitter)…
  @early_slack_ms 400
  # …and no later than this after it (two passes of even the slowest ring, plus slack).
  @late_limit_ms 7_000

  # At least this long between two casts, so a client can't spray casts at the server.
  @min_cast_gap_ms 1_000

  # How near the rod's post you must stand to take the rod.
  @post_reach 90.0

  @doc "The starter rod's item definition id."
  def rod_id, do: @rod_id

  @doc "Every catch the water can give (the default set)."
  def catches, do: @catches

  @doc "The catch with this item definition id, or nil."
  def find_catch(id), do: Enum.find(@catches, &(&1.id == id))

  @doc "The shortest time allowed between two casts (ms)."
  def min_cast_gap_ms, do: @min_cast_gap_ms

  @doc """
  The item definitions fishing needs: the rod and every catch. Seeded with the rest of the item defs
  (`Server.Seeds`); `base_attributes` carries what the client draws and the hotbar uses.
  """
  def item_defs do
    rod = %{
      item_def_id: @rod_id,
      name: "Fishing Rod",
      category: "tool",
      slot: "hand",
      stackable: false,
      base_attributes: %{"key" => "rod", "use" => "fish"}
    }

    catches =
      for c <- @catches do
        %{
          item_def_id: c.id,
          name: c.name,
          category: c.kind,
          slot: nil,
          stackable: true,
          base_attributes:
            %{"key" => c.key, "color" => c.color}
            |> then(fn a -> if c.sell, do: Map.put(a, "sell", c.sell), else: a end)
        }
      end

    [rod | catches]
  end

  @doc "Upsert fishing's item definitions (idempotent)."
  def seed_definitions do
    for attrs <- item_defs() do
      %ItemDefinition{}
      |> ItemDefinition.changeset(attrs)
      |> Repo.insert!(
        on_conflict: {:replace, [:name, :category, :slot, :stackable, :base_attributes]},
        conflict_target: :item_def_id
      )
    end

    :ok
  end

  @doc """
  Roll what's on the line. `uniform` is a 0..1 random number (taken as an argument so tests can pin it).
  """
  @spec roll(float()) :: map()
  def roll(uniform) when is_float(uniform) or is_integer(uniform) do
    total = Enum.reduce(@catches, 0.0, &(&1.weight + &2))
    target = min(max(uniform * 1.0, 0.0), 0.999_999) * total

    Enum.reduce_while(@catches, 0.0, fn c, acc ->
      acc = acc + c.weight
      if target < acc, do: {:halt, c}, else: {:cont, acc}
    end)
    |> case do
      %{} = c -> c
      _ -> List.last(@catches)
    end
  end

  @doc "How long until the bite (ms), from a 0..1 random number."
  @spec wait_ms(float()) :: non_neg_integer()
  def wait_ms(uniform) do
    u = min(max(uniform * 1.0, 0.0), 1.0)
    # The range can be overridden in config (the test suite sets it to {0, 0} so a reel needn't wait).
    {lo, hi} = Application.get_env(:server, __MODULE__, [])[:wait_range] || {@wait_min_ms, @wait_max_ms}
    round(lo + u * (hi - lo))
  end

  @doc """
  Whether a reel at `now` counts for a hook made at `cast_at` with a bite due `wait_ms` later: not before
  the bite (allowing a little network slack), and not after the ring could have run out.
  """
  @spec reel_in_time?(integer(), non_neg_integer(), integer()) :: boolean()
  def reel_in_time?(cast_at, wait_ms, now) do
    bite = cast_at + wait_ms
    now >= bite - @early_slack_ms and now <= bite + @late_limit_ms
  end

  @doc """
  Whether this world lets you fish. On by default everywhere there's water (U-6); a world opts out with
  `"fishing": false` in its spec core (U-10).
  """
  @spec allowed?(map() | nil) :: boolean()
  def allowed?(core) when is_map(core), do: Map.get(core, "fishing", true) != false
  def allowed?(_), do: true

  @doc """
  Whether `pos` ([x, y], our last reported position) is at a prop in this world's spec core that gives
  out a rod (`"gives": "rod"`). The starter rod's post in the Vale.
  """
  @spec at_rod_post?(map() | nil, list() | nil) :: boolean()
  def at_rod_post?(core, [x, y]) when is_map(core) and is_number(x) and is_number(y) do
    props = Map.get(core, "props", [])

    is_list(props) and
      Enum.any?(props, fn p ->
        with true <- is_map(p),
             "rod" <- Map.get(p, "gives"),
             [px, py] when is_number(px) and is_number(py) <- Map.get(p, "position") do
          :math.sqrt((x - px) * (x - px) + (y - py) * (y - py)) <= @post_reach
        else
          _ -> false
        end
      end)
  end

  def at_rod_post?(_core, _pos), do: false

  @doc "What the client needs to play the ring for a hook: the wait and the ring's difficulty."
  def hook_payload(haul, wait_ms) do
    %{wait_ms: wait_ms, window: haul.ring.window, speed: haul.ring.speed}
  end

  @doc "What the client is told about a landed catch (and how many of it it now holds)."
  def caught_payload(haul, count) do
    %{item_def_id: haul.id, key: haul.key, name: haul.name, kind: haul.kind, color: haul.color, count: count}
  end
end
