defmodule Server.Devices do
  @moduledoc """
  The devices a player is signed in on (issue 175). A device proves itself with its own random bearer
  token; only the token's SHA-256 is stored (`Server.Device`). This module finds a device by its token,
  adds one (first sight, or a "Link a device" the owner allowed), lists them for the owner, and signs
  one out.

  Tokens never leave this module except as hashes, and are never logged.
  """
  import Ecto.Query
  alias Server.{Device, Friends, Repo}

  # How many devices one account may be signed in on at once. Plenty for a person; a ceiling for a
  # code that leaks.
  @max_devices 10

  # Long enough for "Sam's phone", short enough for a list row.
  @max_name 40

  @doc "The stored form of a device token: lowercase hex SHA-256 (the backfill computes the same)."
  @spec hash_token(String.t()) :: String.t()
  def hash_token(token) when is_binary(token),
    do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  @doc "A device name as the player sent it: trimmed and capped, or nil when there's nothing to keep."
  @spec clean_name(term()) :: String.t() | nil
  def clean_name(name) when is_binary(name) do
    case name |> String.trim() |> String.slice(0, @max_name) |> String.trim() do
      "" -> nil
      clean -> clean
    end
  end

  def clean_name(_), do: nil

  @doc "The most devices one account may hold."
  def max_devices, do: @max_devices

  @doc "The device a token belongs to (revoked or not), or nil."
  @spec by_token(String.t()) :: Device.t() | nil
  def by_token(token) when is_binary(token), do: Repo.get_by(Device, token_hash: hash_token(token))

  @doc "Whether some device (revoked or not) already holds this token hash."
  @spec hash_taken?(String.t()) :: boolean()
  def hash_taken?(token_hash), do: Repo.exists?(from(d in Device, where: d.token_hash == ^token_hash))

  @doc "A device that is still signed in, by id, or nil."
  @spec get_active(term()) :: Device.t() | nil
  def get_active(device_id) do
    case Ecto.UUID.cast(device_id) do
      {:ok, id} -> Repo.one(from(d in Device, where: d.device_id == ^id and is_nil(d.revoked_at)))
      :error -> nil
    end
  end

  @doc "Note that a device was just used, and take its new name if it sent one."
  @spec touch(Device.t(), String.t() | nil) :: Device.t()
  def touch(%Device{} = device, name \\ nil) do
    changes = %{last_seen_at: DateTime.utc_now()}
    changes = if name, do: Map.put(changes, :name, name), else: changes

    case device |> Ecto.Changeset.change(changes) |> Repo.update() do
      {:ok, device} -> device
      {:error, _} -> device
    end
  end

  @doc """
  Add a device to an account, carrying a token hash. `{:error, :too_many}` at the cap, `{:error,
  :taken}` if the hash already belongs to a device.
  """
  @spec add(Ecto.UUID.t(), String.t(), String.t() | nil) :: {:ok, Device.t()} | {:error, :too_many | :taken}
  def add(user_id, token_hash, name) do
    if count_active(user_id) >= @max_devices do
      {:error, :too_many}
    else
      %Device{}
      |> Device.changeset(%{
        user_id: user_id,
        token_hash: token_hash,
        name: name || "Device",
        last_seen_at: DateTime.utc_now()
      })
      |> Repo.insert()
      |> case do
        {:ok, device} -> {:ok, device}
        {:error, _} -> {:error, :taken}
      end
    end
  end

  @doc "How many devices an account is signed in on."
  @spec count_active(Ecto.UUID.t()) :: non_neg_integer()
  def count_active(user_id) do
    Repo.aggregate(from(d in Device, where: d.user_id == ^user_id and is_nil(d.revoked_at)), :count)
  end

  @doc """
  The owner's view of their devices: signed-in ones only, this one first, then the most recently seen.
  """
  @spec list_view(Ecto.UUID.t(), Ecto.UUID.t() | nil) :: [map()]
  def list_view(user_id, current_id) do
    from(d in Device,
      where: d.user_id == ^user_id and is_nil(d.revoked_at),
      order_by: [desc_nulls_last: d.last_seen_at, asc: d.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn d ->
      %{
        id: d.device_id,
        name: d.name,
        last_seen_ms: d.last_seen_at && DateTime.to_unix(d.last_seen_at, :millisecond),
        current: d.device_id == current_id
      }
    end)
    |> Enum.sort_by(&(not &1.current))
  end

  @doc """
  Sign out ANOTHER of the owner's devices. Its live sockets are told (`signed_out`) and dropped, and
  the owner's clients get a fresh device list. The device you're on, or someone else's, is refused.
  """
  @spec revoke(Ecto.UUID.t(), Ecto.UUID.t() | nil, term()) :: :ok | {:error, :not_found | :current}
  def revoke(user_id, current_id, device_id) do
    with {:ok, id} <- Ecto.UUID.cast(device_id),
         true <- id != current_id || :current,
         {1, _} <-
           Repo.update_all(
             from(d in Device, where: d.device_id == ^id and d.user_id == ^user_id and is_nil(d.revoked_at)),
             set: [revoked_at: DateTime.utc_now(), updated_at: DateTime.utc_now()]
           ) do
      Friends.notify(user_id, {:signed_out, id})
      Friends.notify(user_id, {:devices_changed})
      :ok
    else
      :current -> {:error, :current}
      _ -> {:error, :not_found}
    end
  end
end
