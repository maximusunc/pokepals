defmodule Server.Whereabouts do
  @moduledoc """
  Where a player last stood, kept in Postgres so it survives disconnects AND server restarts: a
  returning player resumes in the world they were in, at the spot they left, rather than at the
  Vale's spawn.

  The channel tracks the player's latest reported position as their transforms arrive (`position/1`),
  writes it here every so often while they move and once more when they leave (`remember/3`), and on a
  cold boot's join reads it back (`recall/1`) to decide where they resume (`resume_target/2`).
  """
  alias Server.{Friends, Homes, PlayerLocation, Repo, Worlds}

  @limit 1.0e6

  @doc "The player position `[x, y]` in a client transform packet (its `\"p\"`), or nil if it has none usable."
  @spec position(term()) :: [number()] | nil
  def position(%{"p" => [x, y]}) when is_number(x) and is_number(y) do
    if abs(x) <= @limit and abs(y) <= @limit, do: [x * 1.0, y * 1.0], else: nil
  end

  def position(_), do: nil

  @doc "Record that `user_id` is standing at `[x, y]` in `world_id` (last write wins)."
  @spec remember(Ecto.UUID.t(), String.t(), [number()]) :: :ok
  def remember(user_id, world_id, [x, y]) when is_binary(user_id) and is_binary(world_id) do
    now = DateTime.utc_now()

    Repo.insert_all(
      PlayerLocation,
      [%{user_id: user_id, world_id: world_id, x: x * 1.0, y: y * 1.0, inserted_at: now, updated_at: now}],
      on_conflict: {:replace, [:world_id, :x, :y, :updated_at]},
      conflict_target: :user_id
    )

    :ok
  end

  @doc "Where `user_id` last stood: `%{world_id: String, p: [x, y]}`, or nil if we've never seen them move."
  @spec recall(Ecto.UUID.t()) :: %{world_id: String.t(), p: [float()]} | nil
  def recall(user_id) when is_binary(user_id) do
    case Repo.get(PlayerLocation, user_id) do
      nil -> nil
      %PlayerLocation{world_id: world_id, x: x, y: y} -> %{world_id: world_id, p: [x, y]}
    end
  end

  @doc """
  Where a cold-booting `user_id` who asked to join `requested_world` should actually resume:

    * `{:here, [x, y]}` — they were last in this very world: set them down at that spot.
    * `{:elsewhere, world_id}` — they were last in another world they can still enter: go there.
    * `:none` — nothing to resume (a new player, or their last world is gone / closed to them).

  A home world is resumable only for its owner or a friend it's open to — never on a one-off invite
  pass, which a resume must not spend.
  """
  @spec resume_target(Ecto.UUID.t(), String.t()) :: {:here, [float()]} | {:elsewhere, String.t()} | :none
  def resume_target(user_id, requested_world) do
    case recall(user_id) do
      nil -> :none
      %{world_id: ^requested_world, p: p} -> {:here, p}
      %{world_id: world_id} -> if enterable?(user_id, world_id), do: {:elsewhere, world_id}, else: :none
    end
  end

  defp enterable?(user_id, "home:" <> owner_id) do
    owner_id == user_id or
      (Ecto.UUID.cast(owner_id) != :error and Friends.friends?(user_id, owner_id) and Homes.can_visit?(user_id, owner_id))
  end

  defp enterable?(_user_id, world_id) do
    Ecto.UUID.cast(world_id) != :error and Worlds.get(world_id) != nil
  end
end
