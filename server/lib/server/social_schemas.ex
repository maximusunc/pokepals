defmodule Server.Friendship do
  @moduledoc "One direction of an accepted friendship. Both directions are stored (see Server.Friends)."
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "friendships" do
    field :user_id, :binary_id, primary_key: true
    field :friend_id, :binary_id, primary_key: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

defmodule Server.FriendRequest do
  @moduledoc "A pending friend request from one player to another."
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "friend_requests" do
    field :from_id, :binary_id, primary_key: true
    field :to_id, :binary_id, primary_key: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

defmodule Server.Block do
  @moduledoc "One player has blocked another: no requests, no invites, no seeing each other's home."
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "blocks" do
    field :blocker_id, :binary_id, primary_key: true
    field :blocked_id, :binary_id, primary_key: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

defmodule Server.Home do
  @moduledoc """
  A player's home state (Server.Homes): closed to visits or not, the keepsakes the companion chose to
  display (favourite first), how many keepsake spots the bond has opened, and the owner's companion
  look for the stand-in that naps at home while they're away.
  """
  use Ecto.Schema

  @primary_key {:owner_id, :binary_id, autogenerate: false}
  schema "homes" do
    field :closed, :boolean, default: false
    field :keepsakes, {:array, :string}, default: []
    field :spots, :integer, default: 3
    field :resident, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end
