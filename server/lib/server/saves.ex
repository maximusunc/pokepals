defmodule Server.Saves do
  @moduledoc """
  The persistence boundary for a player's opaque blobs — companion + appearance — now keyed by the
  internal `user_id` (the token is resolved to a user_id once, at connect; see `Server.Accounts`).
  Keeps Repo access out of the channel. The server is the sole authority — there is no local game
  save — so `load/1` is what a returning player gets and `store/3` is the canonical write.

  Both blobs stay OPAQUE: the server stores and returns them without interpreting a field.
  """
  alias Server.{Appearance, Companion, Repo}

  @doc """
  The saved companion + appearance for a user. Either is `nil` for a brand-new player who has not
  saved that blob yet (the account exists, but no companion/appearance row does).
  """
  @spec load(Ecto.UUID.t()) :: %{companion: map() | nil, appearance: map() | nil}
  def load(user_id) when is_binary(user_id) do
    companion = Repo.get_by(Companion, user_id: user_id)
    appearance = Repo.get(Appearance, user_id)

    %{
      companion: companion && companion.data,
      appearance: appearance && appearance.data
    }
  end

  @doc """
  Upsert a player's companion + appearance blobs (last write wins). Both are written in one
  transaction so a save never lands half-applied. `nil` is coerced to `%{}` to satisfy the NOT NULL
  jsonb columns; the client always sends both as maps anyway.
  """
  @spec store(Ecto.UUID.t(), map() | nil, map() | nil) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()}
  def store(user_id, companion, appearance) when is_binary(user_id) do
    Repo.transaction(fn ->
      with {:ok, c} <- upsert_companion(user_id, companion || %{}),
           {:ok, a} <- upsert_appearance(user_id, appearance || %{}) do
        %{companion: c, appearance: a}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp upsert_companion(user_id, data) do
    %Companion{}
    |> Companion.changeset(%{user_id: user_id, data: data})
    |> Repo.insert(
      on_conflict: {:replace, [:data, :updated_at]},
      conflict_target: :user_id
    )
  end

  defp upsert_appearance(user_id, data) do
    %Appearance{}
    |> Appearance.changeset(%{user_id: user_id, data: data})
    |> Repo.insert(
      on_conflict: {:replace, [:data, :updated_at]},
      conflict_target: :user_id
    )
  end
end
