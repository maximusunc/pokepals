defmodule Server.AmbientPals do
  @moduledoc """
  The server-authoritative AMBIENT PALS for one world: small creatures that wander and loiter as shared
  set-dressing, so the world reads as alive even when few players are online (the SVG's "ambient pals —
  not yours"). Pure logic (no process, no I/O) — `Server.World` owns one per world, ticks it ~10 Hz, and
  fans the resulting transforms out on the world's state topic, so every player sees the same pal in the
  same spot.

  Each pal runs a tiny PAUSE → ROAM machine: it rests, picks a random point within `roam_radius` of its
  `home`, ambles there at a gentle speed, then rests again. It carries its own reproducible RNG stream
  (seeded from its id), so the wander is varied between pals but stable across a process restart — no
  wall-clock or global randomness leaks in.

  ## Obstacle avoidance (server-authoritative)

  Pals avoid the world's solids: they never aim a wander target into one, slide around any they graze,
  and start clear of one their home sits on. This is the Elixir port of the client's `Solids` — it
  builds the SAME circle obstacles from the spec (hand-placed `trees`, great-tree `landmarks`, the tall
  `props`, and blocking `ponds`) and resolves with the same clamp-to-bounds + push-out-of-circles pass,
  using a pal body radius of `collision.body_radius + collision.margin`.

  The border-ring treeline is generated server-side now (`Server.WorldBorder`) and baked into the spec as
  `border_trees`; the sim adds those as tree circles like any other, so pals avoid the real treeline — the
  same points the client draws and collides its avatars against. Only hedge segment walls are skipped
  (they exist just in the maze, which has no pals). A pal that gets wedged abandons its target after a
  moment (the stuck-guard) rather than grinding into a trunk forever.

  Wire shape (`to_list/1`): `[%{id: String, p: [x, y], l: [lx, ly], s: String, v: integer}]` — position,
  a facing unit vector (the same `[x, y]` JSON encoding the live-transform fan-out uses), and the pal's
  current animal `s`pecies + coat `v`ariant so every client renders (and re-renders, on a shift) the same
  form. A formless pal (no seed species — the client's companion-puppet fallback) reports `s: ""`.
  """

  @speed 26.0          # px/sec while roaming — an unhurried amble
  @arrive 4.0          # px: close enough to a target to count as arrived
  @pause_min 1.2       # seconds at rest before choosing a new wander target
  @pause_max 3.6
  @linger_min 0.6      # seconds to settle on arrival before the next pause window
  @linger_max 2.0
  @default_roam 80.0
  @target_tries 8      # how many times to re-roll a wander target that lands in a solid
  @stuck_limit 1.2     # seconds of no progress before a wedged pal gives up its target
  @default_radius 8.0  # fallback pal body radius if the spec has no collision block

  # Daemon-style FORM ROTATION: a species-bearing pal occasionally shifts into a DIFFERENT animal, in the
  # spirit of the bonded companion's daemon form. It's decided HERE, in the shared sim, so every client
  # sees the same animal at the same moment (the sim is the one source of truth, like the positions).
  # The species table must mirror the client's data/pals.json variant counts exactly, the same way
  # @solid_types mirrors the client's Solids.SOLID_TYPES.
  @species %{"cat" => 4, "fox" => 3, "rabbit" => 4, "bird" => 4, "wolf" => 4}
  @morph_min 45.0      # seconds between shifts — a random point in this window, per pal
  @morph_max 120.0

  # Built-in "solid" prop types and their blocking radii — must match the client's `Solids.SOLID_TYPES`.
  @solid_types %{
    "bench" => 11.0,
    "signpost" => 7.0,
    "lantern" => 6.0,
    "crystal" => 9.0,
    "log" => 13.0,
    "berry_bush" => 9.0
  }

  defstruct pals: [], obstacles: [], bounds: nil, radius: @default_radius

  @doc """
  Build the sim from a world spec's `core` map. Reads `ambient_pals` (the pals) plus the geometry it
  must avoid (`trees`/`landmarks`/`props`/`ponds`/`collision`/`bounds`). Returns an empty sim if the
  world has no pals.
  """
  def new(core) when is_map(core) do
    defs = Map.get(core, "ambient_pals", [])

    if is_list(defs) and defs != [] do
      geom = %__MODULE__{
        obstacles: build_obstacles(core),
        bounds: build_bounds(core),
        radius: build_radius(core)
      }

      pals =
        defs
        |> Enum.with_index()
        |> Enum.map(fn {d, i} -> seed_pal(d, i, geom) end)
        |> Enum.reject(&is_nil/1)

      %{geom | pals: pals}
    else
      %__MODULE__{}
    end
  end

  def new(_), do: %__MODULE__{}

  @doc "Whether this world has any ambient pals (so `Server.World` can skip ticking when it doesn't)."
  def any?(%__MODULE__{pals: pals}), do: pals != []

  @doc "Advance every pal by `dt` seconds (wander + form rotation), returning the new sim state."
  def tick(%__MODULE__{pals: pals} = state, dt) when is_number(dt) do
    %{state | pals: Enum.map(pals, fn p -> p |> morph_step(dt) |> step(dt, state) end)}
  end

  @doc "The current pal transforms as the client wire shape: `[%{id, p: [x, y], l: [lx, ly], s, v}]`."
  def to_list(%__MODULE__{pals: pals}) do
    Enum.map(pals, fn p ->
      {px, py} = p.pos
      {lx, ly} = p.facing
      %{id: p.id, p: [px, py], l: [lx, ly], s: p.species, v: p.variant}
    end)
  end

  # --- pal lifecycle ---

  defp seed_pal(d, i, geom) when is_map(d) do
    id = to_string(Map.get(d, "id", "pal_#{i}"))
    home = vec(Map.get(d, "home", [0, 0]))
    roam = num(Map.get(d, "roam_radius", @default_roam))
    rng = :rand.seed_s(:exsp, {:erlang.phash2(id), i + 1, 1})
    {pause, rng} = rand_range(rng, @pause_min, @pause_max)
    species = to_string(Map.get(d, "species", ""))
    variant = int(Map.get(d, "variant", 0))
    # Only a pal that already wears a KNOWN animal rotates; a formless one (the client's companion-puppet
    # fallback) stays formless, since the client can't swap puppet KINDS mid-stream. morph = nil disables it.
    {morph, rng} =
      if Map.has_key?(@species, species), do: rand_range(rng, @morph_min, @morph_max), else: {nil, rng}

    # Start clear of any solid the home happens to sit on (e.g. a pal placed by a log).
    pos = resolve(home, geom)

    %{
      id: id,
      home: home,
      roam: roam,
      look: Map.get(d, "look", %{}),
      pos: pos,
      target: pos,
      facing: {0.0, 1.0},
      phase: :pause,
      timer: pause,
      stuck: 0.0,
      species: species,
      variant: variant,
      morph: morph,
      rng: rng
    }
  end

  defp seed_pal(_, _, _), do: nil

  # Resting: count the pause down, then pick a fresh (obstacle-free) target and start ambling.
  defp step(%{phase: :pause, timer: t} = pal, dt, state) do
    t = t - dt
    if t <= 0.0, do: start_roam(pal, state), else: %{pal | timer: t}
  end

  # Ambling: step toward the target, sliding out of any solid; settle on arrival, give up if wedged.
  defp step(%{phase: :roam, pos: {px, py} = from, target: {tx, ty}} = pal, dt, state) do
    dx = tx - px
    dy = ty - py
    dist = :math.sqrt(dx * dx + dy * dy)
    step_len = @speed * dt

    if dist <= max(@arrive, step_len) do
      {linger, rng} = rand_range(pal.rng, @linger_min, @linger_max)
      %{pal | pos: resolve({tx, ty}, state), phase: :pause, timer: linger, stuck: 0.0, rng: rng}
    else
      resolved = resolve({px + dx / dist * step_len, py + dy / dist * step_len}, state)
      moved = distance(from, resolved)
      stuck = if moved < 0.5 * step_len, do: pal.stuck + dt, else: 0.0

      if stuck > @stuck_limit do
        {linger, rng} = rand_range(pal.rng, @linger_min, @linger_max)
        %{pal | pos: resolved, phase: :pause, timer: linger, stuck: 0.0, rng: rng}
      else
        %{pal | pos: resolved, facing: facing_from(from, resolved) || pal.facing, stuck: stuck}
      end
    end
  end

  # Pick a wander target inside the home disk that isn't sitting in a solid (re-roll up to @target_tries,
  # then settle for home, which is already clear), and head for it.
  defp start_roam(%{home: home, roam: roam, rng: rng} = pal, state) do
    {target, rng} = pick_target(home, roam, rng, state, @target_tries)
    %{pal | phase: :roam, target: target, rng: rng}
  end

  defp pick_target(home, roam, rng, state, tries) do
    {cand, rng} = random_point_in_disk(home, roam, rng)

    cond do
      not blocked?(cand, state) -> {cand, rng}
      tries <= 1 -> {home, rng}
      true -> pick_target(home, roam, rng, state, tries - 1)
    end
  end

  # A uniform random point in the disk of radius `roam` around home (sqrt keeps it uniform, not
  # centre-biased).
  defp random_point_in_disk({hx, hy}, roam, rng0) do
    {ang, rng1} = rand_range(rng0, 0.0, 2.0 * :math.pi())
    {u, rng2} = :rand.uniform_s(rng1)
    radius = roam * :math.sqrt(u)
    {{hx + radius * :math.cos(ang), hy + radius * :math.sin(ang)}, rng2}
  end

  # --- form rotation (the daemon-style shift, decided in the shared sim) ---

  # A formless pal never shifts. A species-bearing one counts its morph timer down and, when it fires,
  # becomes a DIFFERENT animal (random coat) and re-arms — carried on the pal's own reproducible rng.
  defp morph_step(%{morph: nil} = pal, _dt), do: pal

  defp morph_step(%{morph: t, rng: rng} = pal, dt) do
    t = t - dt

    if t <= 0.0 do
      {species, variant, rng} = roll_form(pal.species, rng)
      {next, rng} = rand_range(rng, @morph_min, @morph_max)
      %{pal | species: species, variant: variant, morph: next, rng: rng}
    else
      %{pal | morph: t}
    end
  end

  # Pick a species other than `current` (so a shift is always visible) and a random coat within it.
  defp roll_form(current, rng) do
    names = Map.keys(@species) -- [current]
    names = if names == [], do: Map.keys(@species), else: names
    {i, rng} = uniform_int(rng, length(names))
    species = Enum.at(names, i)
    {v, rng} = uniform_int(rng, Map.fetch!(@species, species))
    {species, v, rng}
  end

  # A uniform integer in 0..n-1, threading the pal's rng (n >= 1).
  defp uniform_int(rng, n) do
    {r, rng} = :rand.uniform_s(n, rng)
    {r - 1, rng}
  end

  # --- collision: the Elixir port of the client's Solids.build / Solids.resolve (circles only) ---

  defp build_obstacles(core) do
    cfg = Map.get(core, "collision", %{})
    tree_r = num(Map.get(cfg, "tree_radius", 7.0))
    great_r = num(Map.get(cfg, "great_tree_radius", 16.0))
    pond_blocks = Map.get(cfg, "pond_blocks", true) == true

    trees = for t <- list(Map.get(core, "trees")), do: %{c: vec(t), r: tree_r}
    # The server-generated border treeline (baked into the spec as `border_trees`), each a tree circle.
    border = for t <- list(Map.get(core, "border_trees")), do: %{c: vec(t), r: tree_r}
    landmarks = for lm <- list(Map.get(core, "landmarks")), do: %{c: vec(Map.get(lm, "position", [0, 0])), r: great_r}

    props =
      for it <- list(Map.get(core, "props")),
          type = to_string(Map.get(it, "type", "")),
          solid?(it, type),
          do: %{c: vec(Map.get(it, "position", [0, 0])), r: prop_radius(it, type)}

    ponds =
      if pond_blocks do
        single = case Map.get(core, "pond") do
          p when is_map(p) -> [pond_solid(p)]
          _ -> []
        end

        single ++ Enum.map(list(Map.get(core, "ponds")), &pond_solid/1)
      else
        []
      end

    trees ++ border ++ landmarks ++ props ++ ponds
  end

  defp solid?(it, type), do: Map.get(it, "solid", Map.has_key?(@solid_types, type)) == true
  defp prop_radius(it, type), do: num(Map.get(it, "collision_radius", Map.get(@solid_types, type, 8.0)))
  defp pond_solid(p), do: %{c: vec(Map.get(p, "center", [0, 0])), r: num(Map.get(p, "radius", 0.0))}

  defp build_bounds(core) do
    case Map.get(core, "bounds") do
      %{"min" => [minx, miny | _], "max" => [maxx, maxy | _]} ->
        {num(minx), num(miny), num(maxx), num(maxy)}

      _ ->
        nil
    end
  end

  defp build_radius(core) do
    cfg = Map.get(core, "collision", %{})
    num(Map.get(cfg, "body_radius", 6.0)) + num(Map.get(cfg, "margin", 2.0))
  end

  # Keep a body of the sim's pal radius inside bounds and out of every circle: clamp, then two push
  # passes each followed by a clamp (corner stability), exactly like Solids.resolve.
  defp resolve(pos, %__MODULE__{obstacles: obs, bounds: bounds, radius: r}) do
    pos
    |> clamp_bounds(r, bounds)
    |> push_out(obs, r)
    |> clamp_bounds(r, bounds)
    |> push_out(obs, r)
    |> clamp_bounds(r, bounds)
  end

  defp push_out(point, obs, r) do
    Enum.reduce(obs, point, fn %{c: {cx, cy}, r: orr}, {x, y} ->
      dx = x - cx
      dy = y - cy
      dist = :math.sqrt(dx * dx + dy * dy)
      min_dist = r + orr

      if dist < min_dist do
        {dx, dy, dist} = if dist < 0.0001, do: {0.0, -1.0, 0.0001}, else: {dx, dy, dist}
        {cx + dx / dist * min_dist, cy + dy / dist * min_dist}
      else
        {x, y}
      end
    end)
  end

  # Whether a point lies inside any solid (used to reject wander targets before committing to them).
  defp blocked?({x, y}, %__MODULE__{obstacles: obs, radius: r}) do
    Enum.any?(obs, fn %{c: {cx, cy}, r: orr} ->
      dx = x - cx
      dy = y - cy
      dx * dx + dy * dy < (r + orr) * (r + orr)
    end)
  end

  defp clamp_bounds({x, y}, _r, nil), do: {x, y}

  defp clamp_bounds({x, y}, r, {minx, miny, maxx, maxy}) do
    {clampf(x, minx + r, maxx - r), clampf(y, miny + r, maxy - r)}
  end

  # --- small helpers ---

  defp facing_from({ax, ay}, {bx, by}) do
    dx = bx - ax
    dy = by - ay
    d = :math.sqrt(dx * dx + dy * dy)
    if d < 0.0001, do: nil, else: {dx / d, dy / d}
  end

  defp distance({ax, ay}, {bx, by}), do: :math.sqrt(:math.pow(bx - ax, 2) + :math.pow(by - ay, 2))

  defp rand_range(rng, lo, hi) do
    {r, rng} = :rand.uniform_s(rng)
    {lo + r * (hi - lo), rng}
  end

  defp clampf(v, lo, hi), do: v |> max(lo) |> min(hi)

  defp list(l) when is_list(l), do: l
  defp list(_), do: []

  defp vec([x, y | _]), do: {num(x), num(y)}
  defp vec(_), do: {0.0, 0.0}

  defp num(n) when is_number(n), do: n * 1.0
  defp num(_), do: 0.0

  defp int(n) when is_number(n), do: trunc(n)
  defp int(_), do: 0
end
