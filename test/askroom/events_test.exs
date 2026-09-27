defmodule Askroom.EventsTest do
  use Askroom.DataCase, async: true

  import Askroom.AccountsFixtures
  import Askroom.EventsFixtures

  alias Askroom.Events
  alias Askroom.Events.{Event, PollAnswer, Vote}
  alias Askroom.Repo

  describe "create_event/2" do
    test "creates an event owned by the presenter, open, unmoderated by default" do
      presenter = presenter_fixture()

      assert {:ok, event} = Events.create_event(presenter, %{title: "Quarterly all-hands"})

      assert event.title == "Quarterly all-hands"
      assert event.presenter_id == presenter.id
      assert event.status == :open
      assert event.moderation_enabled == false
    end

    test "assigns a 6-character join code from the unambiguous alphabet" do
      event = event_fixture()

      assert String.length(event.join_code) == 6
      refute String.contains?(event.join_code, ["0", "O", "1", "I"])
      assert event.join_code == String.upcase(event.join_code)
    end

    test "each event gets its own join code" do
      presenter = presenter_fixture()
      event_a = event_fixture(%{}, presenter)
      event_b = event_fixture(%{}, presenter)

      refute event_a.join_code == event_b.join_code
    end

    test "requires a title" do
      presenter = presenter_fixture()

      assert {:error, changeset} = Events.create_event(presenter, %{title: ""})
      assert "can't be blank" in errors_on(changeset).title
    end
  end

  describe "get_event/2" do
    test "returns the event when owned by the presenter" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)

      assert {:ok, ^event} = Events.get_event(presenter, event.id)
    end

    test "returns :not_found for another presenter's event" do
      owner = presenter_fixture()
      other = presenter_fixture()
      event = event_fixture(%{}, owner)

      assert {:error, :not_found} = Events.get_event(other, event.id)
    end

    test "returns :not_found for a nonexistent id" do
      presenter = presenter_fixture()

      assert {:error, :not_found} = Events.get_event(presenter, -1)
    end
  end

  describe "get_event_by_join_code/1" do
    test "finds the event, case-insensitively" do
      event = event_fixture()

      assert {:ok, found} = Events.get_event_by_join_code(event.join_code)
      assert found.id == event.id

      assert {:ok, ^found} = Events.get_event_by_join_code(String.downcase(event.join_code))
    end

    test "trims surrounding whitespace" do
      event = event_fixture()

      assert {:ok, found} = Events.get_event_by_join_code("  #{event.join_code}  ")
      assert found.id == event.id
    end

    test "returns :not_found for an unknown code" do
      assert {:error, :not_found} = Events.get_event_by_join_code("ZZZZZZ")
    end
  end

  describe "list_events/1" do
    test "lists only the presenter's own events, newest first" do
      presenter = presenter_fixture()
      other = presenter_fixture()

      older = event_fixture(%{title: "Older"}, presenter)
      newer = event_fixture(%{title: "Newer"}, presenter)
      _theirs = event_fixture(%{title: "Not mine"}, other)

      assert Events.list_events(presenter) |> Enum.map(& &1.id) == [newer.id, older.id]
    end
  end

  describe "update_event/3" do
    test "updates an owned event" do
      presenter = presenter_fixture()
      event = event_fixture(%{title: "Draft title"}, presenter)

      assert {:ok, updated} = Events.update_event(presenter, event, %{title: "Final title"})
      assert updated.title == "Final title"
    end

    test "refuses to update another presenter's event" do
      owner = presenter_fixture()
      other = presenter_fixture()
      event = event_fixture(%{title: "Original"}, owner)

      assert {:error, :not_found} = Events.update_event(other, event, %{title: "Hijacked"})
      assert {:ok, unchanged} = Events.get_event(owner, event.id)
      assert unchanged.title == "Original"
    end
  end

  describe "create_participant/2" do
    test "creates an anonymous participant with no display name" do
      event = event_fixture()

      assert {:ok, participant} = Events.create_participant(event)
      assert participant.event_id == event.id
      assert is_binary(participant.id)
      assert participant.display_name == nil
    end

    test "accepts an optional display name" do
      event = event_fixture()

      assert {:ok, participant} = Events.create_participant(event, %{display_name: "Sam"})
      assert participant.display_name == "Sam"
    end

    test "rejects a display name over 50 characters" do
      event = event_fixture()

      assert {:error, changeset} =
               Events.create_participant(event, %{display_name: String.duplicate("a", 51)})

      assert "should be at most 50 character(s)" in errors_on(changeset).display_name
    end
  end

  describe "create_question/3" do
    test "is visible immediately when the event has moderation disabled" do
      event = event_fixture(%{moderation_enabled: false})
      participant = participant_fixture(event)

      assert {:ok, question} = Events.create_question(event, participant, %{body: "Why?"})
      assert question.status == :visible
      assert question.vote_count == 0
    end

    test "is pending when the event has moderation enabled" do
      event = event_fixture(%{moderation_enabled: true})
      participant = participant_fixture(event)

      assert {:ok, question} = Events.create_question(event, participant, %{body: "Why?"})
      assert question.status == :pending
    end

    test "requires a non-blank body" do
      event = event_fixture()
      participant = participant_fixture(event)

      assert {:error, changeset} = Events.create_question(event, participant, %{body: ""})
      assert "can't be blank" in errors_on(changeset).body
    end

    test "rejects a body over 280 characters" do
      event = event_fixture()
      participant = participant_fixture(event)

      assert {:error, changeset} =
               Events.create_question(event, participant, %{body: String.duplicate("a", 281)})

      assert "should be at most 280 character(s)" in errors_on(changeset).body
    end
  end

  describe "create_poll/3" do
    test "creates a draft poll for an owned event" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)

      assert {:ok, poll} =
               Events.create_poll(presenter, event, %{
                 question_text: "Best framework?",
                 options: ["Phoenix", "Rails"]
               })

      assert poll.status == :draft
      assert poll.options == ["Phoenix", "Rails"]
    end

    test "refuses to create a poll on another presenter's event" do
      owner = presenter_fixture()
      other = presenter_fixture()
      event = event_fixture(%{}, owner)

      assert {:error, :not_found} =
               Events.create_poll(other, event, %{
                 question_text: "Best framework?",
                 options: ["Phoenix", "Rails"]
               })
    end

    test "requires at least 2 options" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)

      assert {:error, changeset} =
               Events.create_poll(presenter, event, %{question_text: "?", options: ["Only one"]})

      assert "should have at least 2 item(s)" in errors_on(changeset).options
    end

    test "rejects duplicate options" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)

      assert {:error, changeset} =
               Events.create_poll(presenter, event, %{
                 question_text: "?",
                 options: ["Same", "Same"]
               })

      assert "can't include duplicate options" in errors_on(changeset).options
    end

    test "rejects a blank option" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)

      assert {:error, changeset} =
               Events.create_poll(presenter, event, %{
                 question_text: "?",
                 options: ["Real option", "   "]
               })

      assert "can't include a blank option" in errors_on(changeset).options
    end
  end

  # Vote and PollAnswer don't have public Events-context functions yet —
  # the atomic-counter voting logic lands in Phase 2, and poll answering
  # in Phase 3. What Phase 1 owns is proving the database itself enforces
  # "one vote per participant per question" (and the poll equivalent),
  # independent of whatever application code eventually calls it.
  describe "database-enforced fairness constraints" do
    test "a participant can only vote once on the same question" do
      event = event_fixture()
      participant = participant_fixture(event)
      question = question_fixture(event, participant)

      assert {:ok, _vote} =
               %Vote{}
               |> Vote.changeset(%{participant_id: participant.id, question_id: question.id})
               |> Repo.insert()

      assert {:error, changeset} =
               %Vote{}
               |> Vote.changeset(%{participant_id: participant.id, question_id: question.id})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).participant_id
    end

    test "different participants can each vote on the same question" do
      event = event_fixture()
      question = question_fixture(event, participant_fixture(event))

      for _ <- 1..3 do
        participant = participant_fixture(event)

        assert {:ok, _vote} =
                 %Vote{}
                 |> Vote.changeset(%{participant_id: participant.id, question_id: question.id})
                 |> Repo.insert()
      end
    end

    test "a participant can only answer the same poll once" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)
      poll = poll_fixture(presenter, event)
      participant = participant_fixture(event)

      assert {:ok, _answer} =
               %PollAnswer{}
               |> PollAnswer.changeset(%{
                 option: "Search",
                 participant_id: participant.id,
                 poll_id: poll.id
               })
               |> Repo.insert()

      assert {:error, changeset} =
               %PollAnswer{}
               |> PollAnswer.changeset(%{
                 option: "Exports",
                 participant_id: participant.id,
                 poll_id: poll.id
               })
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).participant_id
    end
  end

  describe "Event.generate_join_code/0" do
    test "never produces ambiguous characters" do
      for _ <- 1..200 do
        code = Event.generate_join_code()
        assert String.length(code) == 6
        refute String.contains?(code, ["0", "O", "1", "I"])
      end
    end
  end
end
