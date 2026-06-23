defmodule Server.PresenceRelayTest do
  @moduledoc """
  Unit tests for the pure Presence-diff → wire-frame adapter. This is the one subtle piece of the
  Presence migration: a diff must become exactly the `join` / `identity` / `leave` frames the
  (unchanged) Godot client already understands, with no double-spawns and no ghosts.

  Diffs are shaped like real Phoenix.Presence diffs: `%{key => %{metas: [meta, ...]}}` where a meta
  carries `:identity` (plus an irrelevant `:phx_ref`, included here to prove it's tolerated).
  """
  use ExUnit.Case, async: true
  alias Server.PresenceRelay

  defp meta(identity), do: %{metas: [%{identity: identity, phx_ref: "ref"}]}

  test "a fresh peer with no identity yet becomes a bare join" do
    {frames, known} =
      PresenceRelay.diff_to_frames(1, MapSet.new(), %{"2" => meta(%{})}, %{})

    assert frames == [%{t: "join", id: 2}]
    assert MapSet.member?(known, 2)
  end

  test "a fresh peer that already has identity becomes join + identity (in that order)" do
    {frames, known} =
      PresenceRelay.diff_to_frames(1, MapSet.new(), %{"3" => meta(%{"name" => "Mossfen"})}, %{})

    assert frames == [%{t: "join", id: 3}, %{"name" => "Mossfen", t: "identity", id: 3}]
    assert MapSet.member?(known, 3)
  end

  test "an identity update (key in BOTH joins and leaves) is identity-only, never leave+rejoin" do
    {frames, known} =
      PresenceRelay.diff_to_frames(
        1,
        MapSet.new([2]),
        %{"2" => meta(%{"name" => "Mossfen"})},
        %{"2" => meta(%{})}
      )

    assert frames == [%{"name" => "Mossfen", t: "identity", id: 2}]
    assert MapSet.member?(known, 2), "the peer stays known across an update"
  end

  test "a real leave emits a leave frame and drops the peer from known" do
    {frames, known} =
      PresenceRelay.diff_to_frames(1, MapSet.new([2]), %{}, %{"2" => meta(%{})})

    assert frames == [%{t: "leave", id: 2}]
    refute MapSet.member?(known, 2)
  end

  test "leaving an unknown peer is a no-op (never seen by this client)" do
    {frames, known} =
      PresenceRelay.diff_to_frames(1, MapSet.new(), %{}, %{"9" => meta(%{})})

    assert frames == []
    assert MapSet.equal?(known, MapSet.new())
  end

  test "our own id is ignored in every branch" do
    # our own join...
    {frames, known} =
      PresenceRelay.diff_to_frames(1, MapSet.new(), %{"1" => meta(%{"name" => "me"})}, %{})

    assert frames == []
    refute MapSet.member?(known, 1)

    # ...and our own update.
    {frames2, _} =
      PresenceRelay.diff_to_frames(1, MapSet.new(), %{"1" => meta(%{"name" => "me"})}, %{"1" => meta(%{})})

    assert frames2 == []
  end

  test "welcome/diff race: a join for an already-known peer sends identity, not a second join" do
    # Peer 2 was already in `welcome` (so already known); a join diff for it now must NOT re-announce
    # the join (which would double-spawn its puppet) — only its identity, if present.
    {frames, known} =
      PresenceRelay.diff_to_frames(1, MapSet.new([2]), %{"2" => meta(%{"name" => "X"})}, %{})

    assert frames == [%{"name" => "X", t: "identity", id: 2}]
    assert MapSet.member?(known, 2)

    # Same race but identity still empty → nothing at all (no duplicate join).
    {frames2, _} =
      PresenceRelay.diff_to_frames(1, MapSet.new([2]), %{"2" => meta(%{})}, %{})

    assert frames2 == []
  end
end
