defmodule Askroom.EventsTest do
  use Askroom.DataCase, async: true

  import Askroom.AccountsFixtures
  import Askroom.EventsFixtures

  alias Askroom.Events
  alias Askroom.Events.{Event, PollAnswer, Vote}
  alias Askroom.Repo
  alias Ecto.Adapters.SQL.Sandbox

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

  describe "get_participant/2" do
    test "finds a participant scoped to the event" do
      event = event_fixture()
      participant = participant_fixture(event)

      assert {:ok, ^participant} = Events.get_participant(event, participant.id)
    end

    test "returns :not_found for a participant belonging to a different event" do
      participant = participant_fixture(event_fixture())
      other_event = event_fixture()

      assert {:error, :not_found} = Events.get_participant(other_event, participant.id)
    end

    test "returns :not_found for a malformed id instead of raising" do
      event = event_fixture()

      assert {:error, :not_found} = Events.get_participant(event, "not-a-uuid")
      assert {:error, :not_found} = Events.get_participant(event, nil)
    end
  end

  describe "create_question/3 rate limiting" do
    test "rejects a second question from the same participant within 10 seconds" do
      event = event_fixture()
      participant = participant_fixture(event)

      assert {:ok, _question} = Events.create_question(event, participant, %{body: "First?"})

      assert {:error, :rate_limited} =
               Events.create_question(event, participant, %{body: "Second?"})
    end

    test "a different participant is not affected by another's rate limit" do
      event = event_fixture()
      participant_a = participant_fixture(event)
      participant_b = participant_fixture(event)

      assert {:ok, _} = Events.create_question(event, participant_a, %{body: "From A"})
      assert {:ok, _} = Events.create_question(event, participant_b, %{body: "From B"})
    end

    test "allows another question once the rate limit window has passed" do
      event = event_fixture()
      participant = participant_fixture(event)

      assert {:ok, _question} = Events.create_question(event, participant, %{body: "First?"})

      stale = DateTime.add(DateTime.utc_now(), -11, :second) |> DateTime.truncate(:second)

      {:ok, participant} =
        Repo.update(Ecto.Changeset.change(participant, last_question_submitted_at: stale))

      assert {:ok, _question} = Events.create_question(event, participant, %{body: "Second?"})
    end

    test "broadcasts the new question to the event's topic" do
      event = event_fixture()
      participant = participant_fixture(event)
      :ok = Events.subscribe(event)

      assert {:ok, question} = Events.create_question(event, participant, %{body: "Broadcast me"})
      assert_receive {:question_created, ^question}
    end
  end

  describe "list_questions/1" do
    test "only includes visible and answered questions, sorted by votes then newest" do
      event = event_fixture()

      pending_event = event_fixture(%{moderation_enabled: true})
      pending_participant = participant_fixture(pending_event)

      _pending =
        question_fixture(pending_event, pending_participant, %{body: "Awaiting moderation"})

      # A fresh participant per question — the rate limit (correctly)
      # refuses a second submission from the same participant in quick
      # succession, which isn't what this test is about.
      older = question_fixture(event, participant_fixture(event), %{body: "Older, no votes"})
      newer = question_fixture(event, participant_fixture(event), %{body: "Newer, no votes"})
      most_voted = question_fixture(event, participant_fixture(event), %{body: "Most voted"})

      for _ <- 1..3 do
        {:ok, _, _} = Events.toggle_vote(participant_fixture(event), most_voted)
      end

      assert Events.list_questions(event) |> Enum.map(& &1.id) == [
               most_voted.id,
               newer.id,
               older.id
             ]
    end
  end

  describe "voted_question_ids/1" do
    test "returns only the ids this participant voted for" do
      event = event_fixture()
      voter = participant_fixture(event)

      voted_for = question_fixture(event, participant_fixture(event), %{body: "Voted"})
      not_voted_for = question_fixture(event, participant_fixture(event), %{body: "Not voted"})

      {:ok, :voted, _} = Events.toggle_vote(voter, voted_for)

      assert Events.voted_question_ids(voter) == MapSet.new([voted_for.id])
      refute MapSet.member?(Events.voted_question_ids(voter), not_voted_for.id)
    end
  end

  describe "toggle_vote/2" do
    test "casts a vote, then retracts it, then casts it again" do
      event = event_fixture()
      participant = participant_fixture(event)
      question = question_fixture(event, participant_fixture(event))

      assert {:ok, :voted, voted} = Events.toggle_vote(participant, question)
      assert voted.vote_count == 1

      assert {:ok, :unvoted, unvoted} = Events.toggle_vote(participant, question)
      assert unvoted.vote_count == 0

      assert {:ok, :voted, voted_again} = Events.toggle_vote(participant, question)
      assert voted_again.vote_count == 1

      assert Repo.aggregate(Vote, :count) == 1
    end

    test "broadcasts the updated question on vote and unvote" do
      event = event_fixture()
      participant = participant_fixture(event)
      question = question_fixture(event, participant_fixture(event))
      :ok = Events.subscribe(event)

      {:ok, :voted, voted} = Events.toggle_vote(participant, question)
      assert_receive {:question_voted, ^voted}

      {:ok, :unvoted, unvoted} = Events.toggle_vote(participant, question)
      assert_receive {:question_voted, ^unvoted}
    end

    test "concurrent upvotes from many participants converge on the correct count" do
      event = event_fixture()
      question = question_fixture(event, participant_fixture(event))
      participants = for _ <- 1..25, do: participant_fixture(event)

      parent = self()

      tasks =
        Enum.map(participants, fn participant ->
          Task.async(fn ->
            Sandbox.allow(Repo, parent, self())
            Events.toggle_vote(participant, question)
          end)
        end)

      results = Task.await_many(tasks, 10_000)

      assert Enum.all?(results, &match?({:ok, :voted, _}, &1))

      final = Repo.get!(Askroom.Events.Question, question.id)
      assert final.vote_count == 25
      assert Repo.aggregate(Vote, :count) == 25
    end
  end

  describe "open_event/2 and close_event/2" do
    test "closes an open event and broadcasts :event_closed" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)
      :ok = Events.subscribe(event)

      assert {:ok, closed} = Events.close_event(presenter, event)
      assert closed.status == :closed
      assert_receive {:event_closed, ^closed}
    end

    test "reopens a closed event" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)
      {:ok, event} = Events.close_event(presenter, event)

      assert {:ok, reopened} = Events.open_event(presenter, event)
      assert reopened.status == :open
    end

    test "refuses to close another presenter's event" do
      owner = presenter_fixture()
      other = presenter_fixture()
      event = event_fixture(%{}, owner)

      assert {:error, :not_found} = Events.close_event(other, event)
    end
  end

  describe "question moderation" do
    test "approve_question/3 makes a pending question visible" do
      presenter = presenter_fixture()
      event = event_fixture(%{moderation_enabled: true}, presenter)
      participant = participant_fixture(event)
      {:ok, question} = Events.create_question(event, participant, %{body: "Pending?"})
      assert question.status == :pending

      :ok = Events.subscribe(event)
      assert {:ok, approved} = Events.approve_question(presenter, event, question)
      assert approved.status == :visible
      assert_receive {:question_status_changed, ^approved}
    end

    test "mark_question_answered/3 and hide_question/3 transition status" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)
      question = question_fixture(event, participant_fixture(event))

      assert {:ok, answered} = Events.mark_question_answered(presenter, event, question)
      assert answered.status == :answered

      assert {:ok, hidden} = Events.hide_question(presenter, event, answered)
      assert hidden.status == :hidden
    end

    test "moderation actions are scoped to the presenter who owns the event" do
      owner = presenter_fixture()
      other = presenter_fixture()
      event = event_fixture(%{}, owner)
      question = question_fixture(event, participant_fixture(event))

      assert {:error, :not_found} = Events.approve_question(other, event, question)
      assert {:error, :not_found} = Events.hide_question(other, event, question)
    end
  end

  describe "list_questions_for_presenter/1" do
    test "includes pending questions, excludes hidden ones" do
      presenter = presenter_fixture()
      event = event_fixture(%{moderation_enabled: true}, presenter)

      pending = question_fixture(event, participant_fixture(event), %{body: "Pending"})

      to_hide = question_fixture(event, participant_fixture(event), %{body: "Will be hidden"})
      {:ok, _} = Events.hide_question(presenter, event, to_hide)

      ids = Events.list_questions_for_presenter(event) |> Enum.map(& &1.id)
      assert pending.id in ids
      refute to_hide.id in ids
    end
  end

  describe "poll lifecycle" do
    test "launch_poll/3 makes a draft poll live and broadcasts" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)
      poll = poll_fixture(presenter, event)
      :ok = Events.subscribe(event)

      assert {:ok, launched} = Events.launch_poll(presenter, event, poll)
      assert launched.status == :live
      assert_receive {:poll_launched, ^launched}
    end

    test "launching a new poll closes any other poll already live" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)
      poll_a = poll_fixture(presenter, event, %{question_text: "A?"})
      poll_b = poll_fixture(presenter, event, %{question_text: "B?"})

      {:ok, _} = Events.launch_poll(presenter, event, poll_a)
      assert {:ok, _} = Events.launch_poll(presenter, event, poll_b)

      assert {:ok, %{status: :closed}} = Events.get_poll(event, poll_a.id)
      assert Events.current_live_poll(event).id == poll_b.id
    end

    test "close_poll/3 freezes a live poll" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)
      poll = poll_fixture(presenter, event)
      {:ok, poll} = Events.launch_poll(presenter, event, poll)

      :ok = Events.subscribe(event)
      assert {:ok, closed} = Events.close_poll(presenter, event, poll)
      assert closed.status == :closed
      assert_receive {:poll_closed, ^closed}
      assert Events.current_live_poll(event) == nil
    end

    test "polls are scoped to the presenter who owns the event" do
      owner = presenter_fixture()
      other = presenter_fixture()
      event = event_fixture(%{}, owner)
      poll = poll_fixture(owner, event)

      assert {:error, :not_found} = Events.launch_poll(other, event, poll)
    end
  end

  describe "poll_results/1" do
    test "includes every option, 0 for ones nobody chose" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)
      poll = poll_fixture(presenter, event, %{options: ["Rust", "Elixir", "Go"]})
      {:ok, poll} = Events.launch_poll(presenter, event, poll)

      {:ok, _} = Events.answer_poll(event, participant_fixture(event), poll, "Elixir")
      {:ok, _} = Events.answer_poll(event, participant_fixture(event), poll, "Elixir")
      {:ok, _} = Events.answer_poll(event, participant_fixture(event), poll, "Rust")

      assert Events.poll_results(poll) == [{"Rust", 1}, {"Elixir", 2}, {"Go", 0}]
    end
  end

  describe "answer_poll/4" do
    test "records an answer and broadcasts :poll_answered" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)
      poll = poll_fixture(presenter, event)
      {:ok, poll} = Events.launch_poll(presenter, event, poll)
      participant = participant_fixture(event)
      :ok = Events.subscribe(event)

      assert {:ok, _answer} = Events.answer_poll(event, participant, poll, "Search")
      assert_receive {:poll_answered, poll_id}
      assert poll_id == poll.id
    end

    test "rejects answering a poll that isn't live" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)
      poll = poll_fixture(presenter, event)
      participant = participant_fixture(event)

      assert {:error, :poll_not_live} = Events.answer_poll(event, participant, poll, "Search")
    end

    test "rejects an option that isn't one of the poll's own" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)
      poll = poll_fixture(presenter, event)
      {:ok, poll} = Events.launch_poll(presenter, event, poll)
      participant = participant_fixture(event)

      assert {:error, :invalid_option} =
               Events.answer_poll(event, participant, poll, "Nonexistent")
    end

    test "rejects a second answer from the same participant" do
      presenter = presenter_fixture()
      event = event_fixture(%{}, presenter)
      poll = poll_fixture(presenter, event)
      {:ok, poll} = Events.launch_poll(presenter, event, poll)
      participant = participant_fixture(event)

      assert {:ok, _} = Events.answer_poll(event, participant, poll, "Search")
      assert {:error, :already_answered} = Events.answer_poll(event, participant, poll, "Exports")
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
