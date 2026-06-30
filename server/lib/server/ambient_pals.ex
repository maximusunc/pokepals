defmodule Server.AmbientPals do
  @moduledoc """
  The server-authoritative AMBIENT PALS for one world: small creatures that wander and loiter as shared
  set-dressing, so the world feels inhabited even when few players are online. This is PURE logic (no
  process, no I/O) — `Server.World` owns one of these per world, ticks it ~10 Hz, and fans the resulting
  transforms out on the world's state topic; every player therefore sees the same pal in the same spot.

  Each pal runs a tiny PAUSE → ROAM state machine: it rests for a beat, picks a random point within
  `roam_radius` of its `home`, ambles there at a gentle speed, then rests again. It carries its own
  reproducible RNG stream (seeded from its id), so the wander is varied between pals but stable across a
  process restart — no wall-clock or global randomness leaks in.

  This is the GENERIC, player-free distillation of the client's `companion_actions.gd` WanderAction
  (which is coupled to the bonded player + bond); the pals have no brain, no bond, and no awareness of
  players — they are atmosphere. The server has no tree/pond geometry, so a pal stays inside its
  `home ± roam_radius` disk rather than dodging props; author roam areas in open ground.

  Wire shape (`to_list/1`): `[%{id: String, p: [x, y], l: [lx, ly]}]` — position and a facing unit
  vector, the same `[x, y]` JSON encoding the live-transform fan-out uses.
  """

  @speed 26.0          # px/sec while roaming — an unhurried amble
  @arrive 4.0          # px: close enough to a target to count as arrived
  @pause_min 1.2       # seconds at rest before choosing a new wander target
  @pause_max 3.6
  @linger_min 0.6      # seconds to settle on arrival before the next pause window
  @linger_max 2.0
  @default_roam 80.0

  defstruct pals: []

  @doc "Build the sim from a world spec's `ambient_pals` array (each `%{id, home, roam_radius, look}`)."
  def new(defs) when is_list(defs) do
    pals =
      defs
      |> Enum.with_index()
      |> Enum.map(fn {d, i} -> seed_pal(d, i) end)
      |> Enum.reject(&is_nil/1)

    %__MODULE__{pals: pals}
  end

  def new(_), do: %__MODULE__{pals: []}

  @doc "Whether this world has any ambient pals (so `Server.World` can skip ticking when it doesn't)."
  def any?(%__MODULE__{pals: pals}), do: pals != []

  @doc "Advance every pal by `dt` seconds, returning the new sim state."
  def tick(%__MODULE__{pals: pals} = state, dt) when is_number(dt) do
    %{state | pals: Enum.map(pals, &step(&1, dt))}
  end

  @doc "The current pal transforms as the client wire shape: `[%{id, p: [x, y], l: [lx, ly]}]`."
  def to_list(%__MODULE__{pals: pals}) do
    Enum.map(pals, fn p ->
      {px, py} = p.pos
      {lx, ly} = p.facing
      %{id: p.id, p: [px, py], l: [lx, ly]}
    end)
  end

  # --- internals ---

  defp seed_pal(d, i) when is_map(d) do
    id = to_string(Map.get(d, "id", "pal_#{i}"))
    home = vec(Map.get(d, "home", [0, 0]))
    roam = num(Map.get(d, "roam_radius", @default_roam))
    rng = :rand.seed_s(:exsp, {:erlang.phash2(id), i + 1, 1})
    {pause, rng} = rand_range(rng, @pause_min, @pause_max)

    %{
      id: id,
      home: home,
      roam: roam,
      look: Map.get(d, "look", %{}),
      pos: home,
      target: home,
      facing: {0.0, 1.0},
      phase: :pause,
      timer: pause,
      rng: rng
    }
  end

  defp seed_pal(_, _), do: nil

  # Resting: count the pause down, then pick a fresh target and start ambling.
  defp step(%{phase: :pause, timer: t} = pal, dt) do
    t = t - dt
    if t <= 0.0, do: start_roam(pal), else: %{pal | timer: t}
  end

  # Ambling: step toward the target; on arrival, settle into a pause.
  defp step(%{phase: :roam, pos: {px, py}, target: {tx, ty}} = pal, dt) do
    dx = tx - px
    dy = ty - py
    dist = :math.sqrt(dx * dx + dy * dy)
    step_len = @speed * dt

    if dist <= max(@arrive, step_len) do
      {linger, rng} = rand_range(pal.rng, @linger_min, @linger_max)
      %{pal | pos: {tx, ty}, phase: :pause, timer: linger, rng: rng}
    else
      %{pal | pos: {px + dx / dist * step_len, py + dy / dist * step_len}, facing: {dx / dist, dy / dist}}
    end
  end

  # Pick a uniform random point in the disk of radius `roam` around home (sqrt keeps it uniform, not
  # centre-biased), and enter the ROAM phase heading for it.
  defp start_roam(%{home: {hx, hy}, roam: roam, rng: rng0} = pal) do
    {ang, rng1} = rand_range(rng0, 0.0, 2.0 * :math.pi())
    {u, rng2} = :rand.uniform_s(rng1)
    radius = roam * :math.sqrt(u)
    target = {hx + radius * :math.cos(ang), hy + radius * :math.sin(ang)}
    %{pal | phase: :roam, target: target, rng: rng2}
  end

  defp rand_range(rng, lo, hi) do
    {r, rng} = :rand.uniform_s(rng)
    {lo + r * (hi - lo), rng}
  end

  defp vec([x, y]), do: {num(x), num(y)}
  defp vec(_), do: {0.0, 0.0}

  defp num(n) when is_number(n), do: n * 1.0
  defp num(_), do: 0.0
end
