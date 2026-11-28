defmodule Server.Links do
  @moduledoc """
  "Link a device" (issue 175): how a player brings their companion to a new phone or computer without
  a password. On a device they're already signed in on, they ask for a code (`new_code/1`); on the
  new device they type it in. The new device sends the code with a FRESH token of its own
  (`redeem/4`, from `POST /link/redeem`), the owner's signed-in device asks "Let <name> in?", and on
  yes (`answer/2`) the new token becomes one of the account's devices. The new device keeps polling
  until it hears.

  A code is 8 characters from an alphabet with nothing to misread (no 0/O, 1/I/L, ...), shown as
  ABCD-EFGH, good for 10 minutes and for one device. Asking for another voids the last. Codes live in
  Postgres (`Server.LinkCode`, hashed) so a restart or a second node doesn't lose one mid-link.
  Wrong guesses are rate limited (Server.LinkThrottle).
  """
  import Ecto.Query
  alias Server.{Devices, Friends, LinkCode, LinkThrottle, Repo}

  @alphabet ~c"ABCDEFGHJKMNPQRSTUVWXYZ23456789"
  @code_len 8
  @ttl_s 600
  # After an answer, the new device may hear it again for this long (a lost response mustn't strand it).
  @answer_grace_s 300

  @doc "How long a code is good for, in seconds."
  def ttl_s, do: @ttl_s

  @doc """
  A fresh code for this player, as shown to them ("ABCD-EFGH"). Any earlier code of theirs that
  hasn't been answered stops working.
  """
  @spec new_code(Ecto.UUID.t()) :: String.t()
  def new_code(user_id) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(c in LinkCode, where: c.user_id == ^user_id and c.state in ["open", "pending"]),
      set: [state: "void", updated_at: now]
    )

    # Old codes are only kept long enough to answer a late poll; tidy them away as we go.
    Repo.delete_all(from(c in LinkCode, where: c.expires_at < ^DateTime.add(now, -86_400)))

    insert_code(user_id, DateTime.add(now, @ttl_s), 5)
  end

  defp insert_code(user_id, expires_at, tries) do
    code = for _ <- 1..@code_len, into: "", do: <<Enum.random(@alphabet)>>

    %LinkCode{user_id: user_id, code_hash: hash(code), expires_at: expires_at}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint(:code_hash)
    |> Repo.insert()
    |> case do
      {:ok, _} -> String.slice(code, 0, 4) <> "-" <> String.slice(code, 4, 4)
      {:error, _} when tries > 1 -> insert_code(user_id, expires_at, tries - 1)
    end
  end

  @doc """
  A new device offers a code and its fresh token. Returns `:pending` (waiting for the owner; poll
  again), `:linked`, `:denied`, `:invalid`, or `:slow_down` (too many wrong codes lately).

  Polling one's own request never counts against the rate limit; anything else that fails does.
  """
  @spec redeem(term(), term(), term(), term()) :: :pending | :linked | :denied | :invalid | :slow_down
  def redeem(code, token, name, ip) do
    token_hash = if is_binary(token) and token != "", do: Devices.hash_token(token)
    row = if is_binary(code) and token_hash, do: Repo.get_by(LinkCode, code_hash: hash(normalize(code)))
    now = DateTime.utc_now()

    cond do
      row && row.pending_token_hash == token_hash -> poll(row, now)
      LinkThrottle.limited?(ip) -> :slow_down
      true -> offer(row, token_hash, Devices.clean_name(name) || "New device", now, ip)
    end
  end

  # The same device asking again about its own request.
  defp poll(row, now) do
    answered_recently = row.answered_at && DateTime.diff(now, row.answered_at) <= @answer_grace_s

    case row.state do
      "pending" -> if live?(row, now), do: :pending, else: :invalid
      "linked" -> if answered_recently, do: :linked, else: :invalid
      "denied" -> if answered_recently, do: :denied, else: :invalid
      _ -> :invalid
    end
  end

  # A first offer: only an open, unexpired code, with a token no device already holds.
  defp offer(%LinkCode{state: "open"} = row, token_hash, name, now, ip) when is_binary(token_hash) do
    with true <- live?(row, now),
         false <- Devices.hash_taken?(token_hash),
         {1, _} <-
           Repo.update_all(
             from(c in LinkCode, where: c.id == ^row.id and c.state == "open"),
             set: [state: "pending", pending_token_hash: token_hash, pending_name: name, updated_at: now]
           ) do
      Friends.notify(row.user_id, {:link_request, name})
      :pending
    else
      _ -> failed(ip)
    end
  end

  defp offer(_row, _token_hash, _name, _now, ip), do: failed(ip)

  defp failed(ip) do
    LinkThrottle.fail(ip)
    :invalid
  end

  @doc """
  The owner answers the request waiting on their code. `:ok`, or `{:error, :expired}` (nothing is
  waiting any more) or `{:error, :too_many}` (they're signed in on as many devices as an account may
  hold; the new device is turned away).
  """
  @spec answer(Ecto.UUID.t(), boolean()) :: :ok | {:error, :expired | :too_many}
  def answer(user_id, allow) do
    now = DateTime.utc_now()

    row =
      Repo.one(
        from(c in LinkCode,
          where: c.user_id == ^user_id and c.state == "pending" and c.expires_at > ^now,
          order_by: [desc: c.inserted_at],
          limit: 1
        )
      )

    cond do
      row == nil -> {:error, :expired}
      allow != true -> settle(row, "denied", now, :ok)
      true -> link(row, now)
    end
  end

  defp link(row, now) do
    case Devices.add(row.user_id, row.pending_token_hash, row.pending_name) do
      {:ok, _device} ->
        result = settle(row, "linked", now, :ok)
        Friends.notify(row.user_id, {:devices_changed})
        result

      {:error, :too_many} ->
        settle(row, "denied", now, {:error, :too_many})

      {:error, :taken} ->
        settle(row, "denied", now, {:error, :expired})
    end
  end

  defp settle(row, state, now, result) do
    Repo.update_all(
      from(c in LinkCode, where: c.id == ^row.id and c.state == "pending"),
      set: [state: state, answered_at: now, updated_at: now]
    )

    result
  end

  defp live?(row, now), do: DateTime.compare(row.expires_at, now) == :gt

  # Case doesn't matter, and nor do the dash or any spaces the player typed.
  defp normalize(code), do: code |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "")

  defp hash(code), do: :crypto.hash(:sha256, code) |> Base.encode16(case: :lower)
end
