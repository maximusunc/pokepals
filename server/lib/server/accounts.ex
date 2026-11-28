defmodule Server.Accounts do
  @moduledoc """
  The identity boundary: turn a device's anonymous bearer token into the internal `user_id` UUID that
  the rest of the system keys on. A token belongs to a DEVICE (`Server.Devices`), and a device to an
  account, so one player can be signed in on several devices. Everything downstream (saves, presence,
  the economy) speaks `user_id` and never sees a token.

  An unseen token mints a brand-new account with that token as its first device (a new player just
  plays, no signup). A token whose device was signed out is refused, and never mints anything: a
  signed-out phone must not quietly become a stranger's fresh account.
  """
  alias Server.{Account, Device, Devices, Economy, Repo}

  # A brand-new player is seeded with a little spending money so the shop (its first sink) has
  # something to spend the very first time they wander into the bazaar. Granted once, on account
  # creation — never on a returning login — so it's a welcome gift, not a refillable faucet.
  @starting_coins 120

  @doc """
  Resolve a token to its account, creating one on first sight. Returns `{:ok, account}`, `{:error,
  :revoked}` for a signed-out device, or `{:error, reason}` on a genuine DB failure.
  """
  @spec resolve_token(String.t()) :: {:ok, Account.t()} | {:error, term()}
  def resolve_token(token) do
    with {:ok, account, _device} <- resolve_device(token), do: {:ok, account}
  end

  @doc """
  Like `resolve_token/1`, but also returns the device. `name` (already cleaned, or nil) names a device
  seen for the first time.
  """
  @spec resolve_device(String.t(), String.t() | nil) ::
          {:ok, Account.t(), Device.t()} | {:error, term()}
  def resolve_device(token, name \\ nil) when is_binary(token) and token != "" do
    case Devices.by_token(token) do
      %Device{revoked_at: nil} = device -> {:ok, Repo.get!(Account, device.user_id), device}
      %Device{} -> {:error, :revoked}
      nil -> create_account(token, name)
    end
  end

  # A fresh account and its first device, together. If two connections race the same new token, the
  # device's unique token_hash turns the loser's transaction into a rollback (taking its half-made
  # account with it); we then re-read the winner's device so both resolve to the SAME user_id.
  defp create_account(token, name) do
    token_hash = Devices.hash_token(token)

    Repo.transaction(fn ->
      account = Repo.insert!(%Account{})

      %Device{}
      |> Device.changeset(%{
        user_id: account.user_id,
        token_hash: token_hash,
        name: name || "Device",
        last_seen_at: DateTime.utc_now()
      })
      |> Repo.insert()
      |> case do
        {:ok, device} -> {account, device}
        {:error, _} -> Repo.rollback(:race)
      end
    end)
    |> case do
      {:ok, {account, device}} ->
        # Best-effort welcome gift; a currency hiccup must never cost the player their account.
        Economy.grant_currency(account.user_id, "coins", @starting_coins)
        {:ok, account, device}

      {:error, :race} ->
        case Devices.by_token(token) do
          %Device{revoked_at: nil} = device -> {:ok, Repo.get!(Account, device.user_id), device}
          %Device{} -> {:error, :revoked}
          nil -> {:error, :race}
        end
    end
  end
end
