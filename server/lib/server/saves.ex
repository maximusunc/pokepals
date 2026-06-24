defmodule Server.Saves do
  @moduledoc """
  The persistence boundary: load and store a player's companion + wardrobe, keyed by their token.
  Keeps Repo access out of the WebSocket handler. The server is the sole authority — there is no
  local game save on the client — so `load/1` is what a returning player gets, and `store/3` is the
  canonical write.
  """
  alias Server.{PlayerSave, Repo}

  @doc "The saved companion + appearance for a token, or nil for a brand-new player."
  @spec load(String.t()) :: %{companion: map() | nil, appearance: map() | nil} | nil
  def load(player_id) when is_binary(player_id) do
    case Repo.get(PlayerSave, player_id) do
      nil -> nil
      %PlayerSave{} = save -> %{companion: save.companion, appearance: save.appearance}
    end
  end

  @doc "Upsert a player's save. Last write wins on the companion/appearance blobs."
  @spec store(String.t(), map() | nil, map() | nil) :: {:ok, PlayerSave.t()} | {:error, Ecto.Changeset.t()}
  def store(player_id, companion, appearance) when is_binary(player_id) do
    %PlayerSave{}
    |> PlayerSave.changeset(%{player_id: player_id, companion: companion, appearance: appearance})
    |> Repo.insert(
      on_conflict: {:replace, [:companion, :appearance, :updated_at]},
      conflict_target: :player_id
    )
  end
end
