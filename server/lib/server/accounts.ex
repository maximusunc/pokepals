defmodule Server.Accounts do
  @moduledoc """
  The identity boundary: turn the client's anonymous bearer token into the internal `user_id` UUID
  that the rest of the system keys on. This is the token → user_id indirection — the one place that
  knows tokens exist. Everything downstream (saves, presence, and later the economy) speaks `user_id`.
  """
  alias Server.{Account, Economy, Repo}

  # A brand-new player is seeded with a little spending money so the shop (its first sink) has
  # something to spend the very first time they wander into the bazaar. Granted once, on account
  # creation — never on a returning login — so it's a welcome gift, not a refillable faucet.
  @starting_petals 120

  @doc """
  Resolve a token to its account, creating one on first sight (a brand-new player just plays — no
  signup). Returns `{:ok, account}` or `{:error, changeset}` on a genuine DB failure.
  """
  @spec resolve_token(String.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def resolve_token(token) when is_binary(token) and token != "" do
    case Repo.get_by(Account, token: token) do
      %Account{} = account -> {:ok, account}
      nil -> create_account(token)
    end
  end

  # Insert a fresh account for an unseen token. If two connections race the same token, the unique
  # constraint turns the loser into `{:error, _}`; we then re-read the winner's row so both
  # connections resolve to the SAME user_id.
  defp create_account(token) do
    %Account{}
    |> Account.changeset(%{token: token})
    |> Repo.insert()
    |> case do
      {:ok, account} ->
        # Best-effort welcome gift; a currency hiccup must never cost the player their account.
        Economy.grant_currency(account.user_id, "petals", @starting_petals)
        {:ok, account}

      {:error, _changeset} ->
        {:ok, Repo.get_by!(Account, token: token)}
    end
  end
end
