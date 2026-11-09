defmodule Server.Tide do
  @moduledoc """
  Ebbmere's tide: a pure function of shared wall-clock time. The Elixir twin of the client's `TideClock`
  (pokepals/scripts/world/tide_clock.gd); both are held to the same vectors
  (test/fixtures/tide_vectors.json), so the server and every client agree on the water without the server
  simulating or broadcasting anything.

  One cosine per period. PHASE 0 is high water and PHASE 0.5 the lowest:

      level = level_low + (level_high - level_low) * (0.5 + 0.5 * cos(2π · phase))

  The LOW WINDOW is the stretch around phase 0.5 where the level is at or under `yield_level` — the
  "lowest tide" in which the sand-dollar rises. `Server.SecretReveal` asks `low_window?/3` before it
  honours the claim, with a grace period for clock skew and a slow claim.

  `params` is the world spec's `tide` block (string keys): `period_s`, `epoch_s`, `level_low`,
  `level_high`, `yield_level`. Times in are integer unix milliseconds.
  """

  @defaults %{"period_s" => 360.0, "epoch_s" => 0.0, "level_low" => 0.30, "level_high" => 0.78, "yield_level" => 0.345}

  defp f(params, key), do: params |> Map.get(key, Map.fetch!(@defaults, key)) |> to_float()

  defp to_float(n) when is_number(n), do: n * 1.0
  defp to_float(_), do: 0.0

  @doc "The cycle length in whole milliseconds."
  @spec period_ms(map()) :: pos_integer()
  def period_ms(params), do: max(1, round(f(params, "period_s") * 1000.0))

  defp epoch_ms(params), do: round(f(params, "epoch_s") * 1000.0)

  @doc "Where `now_ms` falls in the cycle: 0.0..1.0, 0 = high water, 0.5 = lowest."
  @spec phase(map(), integer()) :: float()
  def phase(params, now_ms) do
    per = period_ms(params)
    Integer.mod(now_ms - epoch_ms(params), per) / per
  end

  @doc "Which tide this is: an integer that steps up at every high water."
  @spec cycle(map(), integer()) :: integer()
  def cycle(params, now_ms) do
    per = period_ms(params)
    d = now_ms - epoch_ms(params)
    Integer.floor_div(d, per)
  end

  @doc "The water level, `level_low`..`level_high`."
  @spec level(map(), integer()) :: float()
  def level(params, now_ms) do
    lo = f(params, "level_low")
    hi = f(params, "level_high")
    lo + (hi - lo) * (0.5 + 0.5 * :math.cos(2.0 * :math.pi() * phase(params, now_ms)))
  end

  @doc """
  Half the width, in seconds, of the low window. 0 if the yield level is at or under the lowest water ever
  reached; half a period if it is never above it.
  """
  @spec low_half_s(map()) :: float()
  def low_half_s(params) do
    lo = f(params, "level_low")
    hi = f(params, "level_high")
    span = hi - lo

    if span <= 0.0 do
      0.0
    else
      c = 2.0 * (f(params, "yield_level") - lo) / span - 1.0
      arg = -c

      cond do
        arg >= 1.0 -> 0.0
        arg <= -1.0 -> f(params, "period_s") * 0.5
        true -> :math.acos(arg) / (2.0 * :math.pi()) * f(params, "period_s")
      end
    end
  end

  @doc "Whether it is lowest tide at `now_ms`, give or take `grace_s` seconds on either side."
  @spec low_window?(map(), integer() | nil, number()) :: boolean()
  def low_window?(params, now_ms, grace_s \\ 0.0)

  def low_window?(params, now_ms, grace_s) when is_map(params) and is_integer(now_ms) do
    from_lowest = abs(phase(params, now_ms) - 0.5) * f(params, "period_s")
    from_lowest <= low_half_s(params) + grace_s
  end

  def low_window?(_params, _now_ms, _grace_s), do: false

  @doc "Seconds until the low window opens (0 when it is open now)."
  @spec seconds_until_low(map(), integer()) :: float()
  def seconds_until_low(params, now_ms) do
    half = low_half_s(params)
    per = f(params, "period_s")
    from_lowest = phase(params, now_ms) * per - per * 0.5

    cond do
      abs(from_lowest) <= half -> 0.0
      from_lowest < 0.0 -> -half - from_lowest
      true -> per - half - from_lowest
    end
  end
end
