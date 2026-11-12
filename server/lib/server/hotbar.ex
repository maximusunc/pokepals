defmodule Server.Hotbar do
  @moduledoc """
  A player's HOTBAR (usable items, U-9 in docs/usable-items-design.md): a row of `size/0` slots holding the
  items they use often, like Minecraft's. Each slot holds an item definition id or `nil` (empty). One slot
  is SELECTED on the client (which one is purely local), and the use button uses whatever is in it.

  Stored server-side so the bar is the same on every device. A newly picked-up usable item drops into the
  first free slot by itself (`place/2`), so the fishing rod is ready to use the moment it's taken. (A bag
  screen to rearrange slots comes later.)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Server.Repo

  @size 5

  @primary_key {:user_id, :binary_id, autogenerate: false}
  schema "hotbars" do
    field :slots, {:array, :integer}, default: []
    timestamps(type: :utc_datetime_usec)
  end

  @doc "How many slots the bar has."
  def size, do: @size

  @doc false
  def changeset(bar, attrs) do
    bar
    |> cast(attrs, [:user_id, :slots])
    |> validate_required([:user_id])
  end

  @doc """
  A user's slots, always exactly `size/0` long: each an item definition id, or `nil` for an empty slot.
  (Stored as integers with `0` meaning empty, since a Postgres integer array can't mix in a nil cleanly.)
  """
  @spec slots(Ecto.UUID.t()) :: [integer() | nil]
  def slots(user_id) do
    stored =
      case Repo.get(__MODULE__, user_id) do
        nil -> []
        bar -> bar.slots || []
      end

    normalize(stored)
  end

  @doc """
  Put `item_def_id` into the first free slot, unless it's already on the bar. Returns the new slots. A
  full bar is left as it is (the item is still owned; it just isn't on the bar).
  """
  @spec place(Ecto.UUID.t(), integer()) :: [integer() | nil]
  def place(user_id, item_def_id) when is_integer(item_def_id) do
    current = slots(user_id)

    cond do
      item_def_id in current ->
        current

      true ->
        case Enum.find_index(current, &is_nil/1) do
          nil -> current
          i -> store(user_id, List.replace_at(current, i, item_def_id))
        end
    end
  end

  # Write the slots (nil stored as 0) and return them as read back.
  defp store(user_id, slots) do
    %__MODULE__{}
    |> changeset(%{user_id: user_id, slots: Enum.map(slots, &(&1 || 0))})
    |> Repo.insert!(on_conflict: {:replace, [:slots, :updated_at]}, conflict_target: :user_id)

    slots
  end

  # Pad or trim to the bar's size, turning the stored 0s back into nils.
  defp normalize(stored) do
    stored
    |> Enum.map(fn v -> if is_integer(v) and v > 0, do: v, else: nil end)
    |> Enum.concat(List.duplicate(nil, @size))
    |> Enum.take(@size)
  end
end
