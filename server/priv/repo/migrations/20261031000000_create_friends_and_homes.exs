defmodule Server.Repo.Migrations.CreateFriendsAndHomes do
  @moduledoc """
  Friends, visiting, and the home's own state (docs/home-world-and-secrets-design.md, FR-0..FR-5 and
  HS-1..HS-6).

    * `accounts` gains a `display_name` (a generated cozy two-word name, FR-0) and a short, unique
      `friend_code` (FR-2). Both are assigned lazily, on first connect.
    * `friendships` holds BOTH directions of an accepted friendship (a→b and b→a), so "my friends" is a
      single indexed lookup. `friend_requests` are the pending ones. `blocks` are one-directional.
    * `homes` is the per-owner home state: whether it's closed to visits, the keepsakes the companion
      chose to display (in order, favourite first), how many keepsake spots the bond has opened, and
      the owner's companion look, so a stand-in can nap at home while they're away.
    * `discoveries` gain what the journal and the companion's choice need: whether the companion was
      beside you (`together`), which friends were near you (`with_ids`), and a snapshot `card` of the
      find (its world, keepsake, qualities and line), so a journal entry outlives later world edits.
  """
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :display_name, :text
      add :friend_code, :text
    end

    create unique_index(:accounts, [:friend_code])

    create table(:friendships, primary_key: false) do
      add :user_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all), primary_key: true
      add :friend_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all), primary_key: true
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create table(:friend_requests, primary_key: false) do
      add :from_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all), primary_key: true
      add :to_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all), primary_key: true
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:friend_requests, [:to_id])

    create table(:blocks, primary_key: false) do
      add :blocker_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all), primary_key: true
      add :blocked_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all), primary_key: true
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create table(:homes, primary_key: false) do
      add :owner_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all), primary_key: true
      add :closed, :boolean, null: false, default: false
      add :keepsakes, {:array, :text}, null: false, default: []
      add :spots, :integer, null: false, default: 3
      add :resident, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    alter table(:discoveries) do
      add :together, :boolean, null: false, default: false
      add :with_ids, {:array, :uuid}, null: false, default: []
      add :card, :map, null: false, default: %{}
    end
  end
end
