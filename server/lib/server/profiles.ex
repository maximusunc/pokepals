defmodule Server.Profiles do
  @moduledoc """
  A player's public face: their generated cozy NAME (FR-0) and short FRIEND CODE (FR-2).

  Names are two friendly words ("Mossy Lantern", "Quiet Fern") drawn from fixed lists, re-rollable
  as often as the player likes. Nothing is ever typed, so nothing needs moderating; free-text names
  wait for moderation (see the design doc). Friend codes are six characters from an alphabet without
  look-alikes (no 0/O, 1/I/L), so they're easy to read aloud. Both are assigned lazily, the first time
  a player connects.
  """
  import Ecto.Query
  alias Server.{Account, Repo}

  @firsts ~w(Mossy Quiet Amber Willow Dappled Misty Hollow Bramble Gentle Sunny Velvet Little Drowsy
             Clover Ember Silver Rainy Honey Maple Cozy Starlit Wander Pebble Fern Thistle Copper Dusky
             Snowy Lantern Tidal Mellow Sleepy Bright Hazel Briar Plum Saffron Cinder Juniper Downy)
  @seconds ~w(Lantern Fern Brook Sparrow Acorn Meadow Thimble Burrow Willow Puddle Kettle Pinecone
              Feather Hollow Bramble Lark Clover Moth Teacup Glimmer Wren Pebble Mitten Hearth Breeze
              Lily Comet Badger Hedgehog Otter Button Cobble Ripple Bluebell Hazelnut Firefly Honeybee Puffin)
  @code_alphabet ~c"23456789ABCDEFGHJKMNPQRSTUVWXYZ"
  @code_length 6

  @doc "A random two-word name. Never the same word twice."
  @spec random_name() :: String.t()
  def random_name do
    first = Enum.random(@firsts)
    second = @seconds |> Enum.reject(&(&1 == first)) |> Enum.random()
    first <> " " <> second
  end

  @doc "Whether a string is a name this module could have generated (used to validate a stamped name)."
  @spec valid_name?(String.t()) :: boolean()
  def valid_name?(name) when is_binary(name) do
    case String.split(name, " ") do
      [a, b] -> a in @firsts and b in @seconds and a != b
      _ -> false
    end
  end

  def valid_name?(_), do: false

  @doc "A random friend code."
  @spec random_code() :: String.t()
  def random_code do
    for(_ <- 1..@code_length, into: "", do: <<Enum.random(@code_alphabet)>>)
  end

  @doc "Normalise a typed friend code: uppercased, spaces and dashes dropped."
  @spec normalise_code(String.t()) :: String.t()
  def normalise_code(code) when is_binary(code) do
    code |> String.upcase() |> String.replace(~r/[\s-]/, "")
  end

  @doc """
  A player's `%{name, friend_code}`, assigning whichever is missing first (a brand-new player gets
  both on their first connect).
  """
  @spec ensure(Ecto.UUID.t()) :: %{name: String.t(), friend_code: String.t()}
  def ensure(user_id) when is_binary(user_id) do
    account = Repo.get!(Account, user_id)
    name = account.display_name || assign_name(user_id)
    code = account.friend_code || assign_code(user_id)
    %{name: name, friend_code: code}
  end

  @doc "Give a player a fresh random name (different from their current one). Returns it."
  @spec reroll_name(Ecto.UUID.t()) :: String.t()
  def reroll_name(user_id) when is_binary(user_id) do
    current = Repo.one(from(a in Account, where: a.user_id == ^user_id, select: a.display_name))
    name = Stream.repeatedly(&random_name/0) |> Enum.find(&(&1 != current))
    set_name(user_id, name)
    name
  end

  @doc "The user_id holding a friend code, or nil."
  @spec user_for_code(String.t()) :: Ecto.UUID.t() | nil
  def user_for_code(code) when is_binary(code) do
    normalised = normalise_code(code)
    Repo.one(from(a in Account, where: a.friend_code == ^normalised, select: a.user_id))
  end

  @doc "Names for a list of user_ids, as a map. Players without a name yet map to \"a wanderer\"."
  @spec names([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => String.t()}
  def names([]), do: %{}

  def names(user_ids) when is_list(user_ids) do
    found =
      Repo.all(from(a in Account, where: a.user_id in ^user_ids, select: {a.user_id, a.display_name}))
      |> Map.new(fn {id, name} -> {id, name || "a wanderer"} end)

    Map.new(user_ids, fn id -> {id, Map.get(found, id, "a wanderer")} end)
  end

  @doc "One player's name."
  @spec name(Ecto.UUID.t()) :: String.t()
  def name(user_id), do: Map.fetch!(names([user_id]), user_id)

  defp assign_name(user_id) do
    name = random_name()
    set_name(user_id, name)
    name
  end

  defp set_name(user_id, name) do
    Repo.update_all(from(a in Account, where: a.user_id == ^user_id), set: [display_name: name])
  end

  # A code collision is vanishingly rare (31^6 ≈ 900M codes), but the unique index is the real guard:
  # on a clash, just try another.
  defp assign_code(user_id, tries \\ 5) do
    code = random_code()

    try do
      Repo.update_all(from(a in Account, where: a.user_id == ^user_id and is_nil(a.friend_code)),
        set: [friend_code: code]
      )

      Repo.one!(from(a in Account, where: a.user_id == ^user_id, select: a.friend_code))
    rescue
      e in Postgrex.Error ->
        if tries > 0, do: assign_code(user_id, tries - 1), else: reraise(e, __STACKTRACE__)
    end
  end
end
