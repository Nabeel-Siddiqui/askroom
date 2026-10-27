defmodule Askroom.Events.VoteBroadcasterTest do
  use ExUnit.Case, async: true

  alias Askroom.Events
  alias Askroom.Events.VoteBroadcaster

  setup do
    name = :"vote_broadcaster_#{System.unique_integer()}"
    pid = start_supervised!({VoteBroadcaster, name: name})
    %{broadcaster: name, pid: pid}
  end

  describe "notify/2" do
    test "broadcasts the event id on Events' own PubSub topic", %{broadcaster: broadcaster} do
      event_id = System.unique_integer([:positive])
      :ok = Events.subscribe(%Events.Event{id: event_id})

      VoteBroadcaster.notify(broadcaster, event_id)

      assert_receive {:question_voted, ^event_id}
    end

    test "coalesces several votes for the same event into one broadcast", %{
      broadcaster: broadcaster
    } do
      event_id = System.unique_integer([:positive])
      :ok = Events.subscribe(%Events.Event{id: event_id})

      VoteBroadcaster.notify(broadcaster, event_id)
      VoteBroadcaster.notify(broadcaster, event_id)
      VoteBroadcaster.notify(broadcaster, event_id)

      assert_receive {:question_voted, ^event_id}
      refute_receive {:question_voted, _}
    end

    test "two different events each get their own broadcast", %{broadcaster: broadcaster} do
      event_a = System.unique_integer([:positive])
      event_b = System.unique_integer([:positive])
      :ok = Events.subscribe(%Events.Event{id: event_a})
      :ok = Events.subscribe(%Events.Event{id: event_b})

      VoteBroadcaster.notify(broadcaster, event_a)
      VoteBroadcaster.notify(broadcaster, event_b)

      assert_receive {:question_voted, ^event_a}
      assert_receive {:question_voted, ^event_b}
    end

    test "a vote for an event already flushed opens a fresh window", %{
      broadcaster: broadcaster
    } do
      event_id = System.unique_integer([:positive])
      :ok = Events.subscribe(%Events.Event{id: event_id})

      VoteBroadcaster.notify(broadcaster, event_id)
      assert_receive {:question_voted, ^event_id}

      VoteBroadcaster.notify(broadcaster, event_id)
      assert_receive {:question_voted, ^event_id}
    end
  end

  describe "sync/1" do
    test "is a no-op round trip", %{broadcaster: broadcaster} do
      assert VoteBroadcaster.sync(broadcaster) == :ok
    end
  end
end
