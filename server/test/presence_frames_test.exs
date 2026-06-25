defmodule Server.PresenceFramesTest do
  @moduledoc """
  Unit tests for the pure Presence-diff → wire-frame adapter. This is the one subtle piece of the
  roster: a diff must become exactly the `join` / `identity` / `leave` frames the Godot client
  understands, with no double-spawns and no ghosts. Frames are `{event, payload}` tuples that
  `Server.WorldChannel` pushes verbatim.

  Diffs are shaped like real Phoenix.Presence diffs: `%{key => %{metas: [meta, ...]}}` where a meta
  carries `:identity` (plus an irrelevant `:phx_ref`, included here to prove it's tolerated).
  """
  use ExUnit.Case, async: true
  alias Server.PresenceFrames

  defp meta(identity), do: %{metas: [%{identity: identity, phx_ref: "ref"}]}

  test "a fresh peer with no identity yet becomes a bare join" do
    {frames, known} =
      PresenceFrames.diff_to_frames(1, MapSet.new(), %{"2" => meta(%{})}, %{})

    assert frames == [{"join", %{id: 2}}]
    assert MapSet.member?(known, 2)
  end

  test "a fresh peer that already has identity becomes join + identity (in that order)" do
    {frames, known} =
      PresenceFrames.diff_to_frames(1, MapSet.new(), %{"3" => meta(%{"name" => "Mossfen"})}, %{})

    assert frames == [{"join", %{id: 3}}, {"identity", %{"name" => "Mossfen", id: 3}}]
    assert MapSet.member?(known, 3)
  end

  test "an identity update (key in BOTH joins and leaves) is identity-only, never leave+rejoin" do
    {frames, known} =
      PresenceFrames.diff_to_frames(
        1,
        MapSet.new([2]),
        %{"2" => meta(%{"name" => "Mossfen"})},
        %{"2" => meta(%{})}
      )

    assert frames == [{"identity", %{"name" => "Mossfen", id: 2}}]
    assert MapSet.member?(known, 2), "the peer stays known across an update"
  end

  test "a real leave emits a leave frame and drops the peer from known" do
    {frames, known} =
      PresenceFrames.diff_to_frames(1, MapSet.new([2]), %{}, %{"2" => meta(%{})})

    assert frames == [{"leave", %{id: 2}}]
    refute MapSet.member?(known, 2)
  end

  test "leaving an unknown peer is a no-op (never seen by this client)" do
    {frames, known} =
      PresenceFrames.diff_to_frames(1, MapSet.new(), %{}, %{"9" => meta(%{})})

    assert frames == []
    assert MapSet.equal?(known, MapSet.new())
  end

  test "our own id is ignored in every branch" do
    # our own join...
    {frames, known} =
      PresenceFrames.diff_to_frames(1, MapSet.new(), %{"1" => meta(%{"name" => "me"})}, %{})

    assert frames == []
    refute MapSet.member?(known, 1)

    # ...and our own update.
    {frames2, _} =
      PresenceFrames.diff_to_frames(1, MapSet.new(), %{"1" => meta(%{"name" => "me"})}, %{
        "1" => meta(%{})
      })

    assert frames2 == []
  end

  test "welcome/diff race: a join for an already-known peer sends identity, not a second join" do
    # Peer 2 was already in `welcome` (so already known); a join diff for it now must NOT re-announce
    # the join (which would double-spawn its puppet) — only its identity, if present.
    {frames, known} =
      PresenceFrames.diff_to_frames(1, MapSet.new([2]), %{"2" => meta(%{"name" => "X"})}, %{})

    assert frames == [{"identity", %{"name" => "X", id: 2}}]
    assert MapSet.member?(known, 2)

    # Same race but identity still empty → nothing at all (no duplicate join).
    {frames2, _} =
      PresenceFrames.diff_to_frames(1, MapSet.new([2]), %{"2" => meta(%{})}, %{})

    assert frames2 == []
  end

  test "peers/2 shapes a presence list into the welcome roster, excluding us" do
    presence_list = %{
      "1" => meta(%{"name" => "me"}),
      "2" => meta(%{"name" => "Mossfen"}),
      "3" => meta(%{})
    }

    peers = PresenceFrames.peers(presence_list, 1) |> Enum.sort_by(& &1.id)

    assert peers == [
             %{id: 2, identity: %{"name" => "Mossfen"}},
             %{id: 3, identity: %{}}
           ]
  end
end
