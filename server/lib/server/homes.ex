defmodule Server.Homes do
  @moduledoc """
  A player's home state, and who may visit it (H3, FR-3, FR-5, HS-3, HS-4).

  Who may come in (`can_visit?/2`): the owner always. Anyone else only while the home is open, with no
  block between them, and either as a **friend** or holding a **one-off pass** from an accepted invite
  (`Server.HomePasses`). Visiting must never happen without consent.

  What it shows comes from the companion: its chosen keepsakes (favourite first) and how many keepsake
  spots the bond has opened. The companion's mind lives on the client, so the CLIENT decides
  (`KeepsakeChoice`) and the server only checks the choice is possible (`set_keepsakes/3`) and stores
  it, which keeps the choice stable between visits and makes a swap something the home can show.
  """
  alias Server.{Discoveries, Friends, Home, HomePasses, Repo}

  @min_spots 3
  @max_spots 7

  @doc "The home's state (defaults for a home that has never been touched)."
  @spec get(Ecto.UUID.t()) :: Home.t()
  def get(owner_id) when is_binary(owner_id) do
    Repo.get(Home, owner_id) || %Home{owner_id: owner_id}
  end

  @doc "The keepsake spot range the bond moves through (HS-3)."
  def spot_range, do: @min_spots..@max_spots

  @doc """
  Store the companion's keepsake choice. `ids` must be discoveries the owner really has (each at most
  once), no more than `spots`, and `spots` must sit in 3..7. Returns `{:ok, home}` or
  `{:error, :invalid}`.
  """
  @spec set_keepsakes(Ecto.UUID.t(), [String.t()], integer()) :: {:ok, Home.t()} | {:error, :invalid}
  def set_keepsakes(owner_id, ids, spots) when is_list(ids) and is_integer(spots) do
    found = MapSet.new(Discoveries.list(owner_id))

    valid =
      spots in spot_range() and length(ids) <= spots and length(Enum.uniq(ids)) == length(ids) and
        Enum.all?(ids, &(is_binary(&1) and MapSet.member?(found, &1)))

    if valid, do: {:ok, upsert(owner_id, keepsakes: ids, spots: spots)}, else: {:error, :invalid}
  end

  def set_keepsakes(_owner_id, _ids, _spots), do: {:error, :invalid}

  @doc "Close (or reopen) the home to every visitor, friends included."
  @spec set_closed(Ecto.UUID.t(), boolean()) :: Home.t()
  def set_closed(owner_id, closed) when is_boolean(closed), do: upsert(owner_id, closed: closed)

  @doc """
  Remember how the owner's companion looks (its resting look + worn form), for the stand-in that naps
  at home while they're away. Only those two presentation keys are kept. Writes only on change.
  """
  @spec set_resident(Ecto.UUID.t(), map()) :: :ok
  def set_resident(owner_id, identity) when is_map(identity) do
    resident = Map.take(identity, ["companion_look", "companion_form"])

    if map_size(resident) > 0 and get(owner_id).resident != resident do
      upsert(owner_id, resident: resident)
    end

    :ok
  end

  @doc "Whether `visitor` may enter `owner`'s home right now (without using up a pass)."
  @spec can_visit?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def can_visit?(owner, owner), do: true

  def can_visit?(visitor, owner) do
    not get(owner).closed and not Friends.blocked_either_way?(visitor, owner) and
      (Friends.friends?(visitor, owner) or HomePasses.valid?(owner, visitor))
  end

  defp upsert(owner_id, changes) do
    home = get(owner_id)
    attrs = Map.merge(Map.take(home, [:closed, :keepsakes, :spots, :resident]), Map.new(changes))
    now = DateTime.utc_now()

    Repo.insert!(
      struct(Home, Map.merge(attrs, %{owner_id: owner_id, inserted_at: home.inserted_at || now, updated_at: now})),
      on_conflict: {:replace, [:closed, :keepsakes, :spots, :resident, :updated_at]},
      conflict_target: :owner_id
    )
  end
end
