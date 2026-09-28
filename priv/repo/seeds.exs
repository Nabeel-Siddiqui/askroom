# Populates the database with a demo presenter and a sample event
# already full of questions and a poll, so a fresh clone (or a public
# demo deployment) has something to look at immediately instead of an
# empty dashboard.
#
#     mix run priv/repo/seeds.exs
#
# Safe to run more than once: it looks the demo presenter and event up
# first and does nothing if they already exist, rather than erroring or
# creating duplicates.

alias Askroom.Accounts
alias Askroom.Accounts.Presenter
alias Askroom.Events
alias Askroom.Events.Event
alias Askroom.Repo

demo_email = "demo@askroom.dev"

presenter =
  case Repo.get_by(Presenter, email: demo_email) do
    nil ->
      {:ok, presenter} =
        Accounts.register_presenter(%{email: demo_email, password: "demo-password-please-change"})

      presenter

    existing ->
      existing
  end

event_title = "Askroom demo talk"

event =
  case Repo.get_by(Event, presenter_id: presenter.id, title: event_title) do
    nil ->
      {:ok, event} = Events.create_event(presenter, %{title: event_title})

      # Each question comes from its own participant, same as real
      # audience members each joining from their own phone — the
      # per-participant rate limit on submitting questions means reusing
      # one participant for all of these wouldn't even work.
      sample_questions = [
        {"What made you choose Elixir for this project?", 5},
        {"How does this handle a talk with a thousand attendees?", 3},
        {"Any plans for a mobile app?", 0}
      ]

      new_participant = fn ->
        {:ok, participant} = Events.create_participant(event)
        participant
      end

      for {body, vote_count} <- sample_questions do
        {:ok, question} = Events.create_question(event, new_participant.(), %{body: body})

        for _ <- 1..vote_count do
          Events.toggle_vote(new_participant.(), question)
        end
      end

      {:ok, poll} =
        Events.create_poll(presenter, event, %{
          question_text: "Which feature should we build next?",
          options: ["Slack integration", "CSV export", "Word cloud"]
        })

      {:ok, poll} = Events.launch_poll(presenter, event, poll)

      for option <- ["Slack integration", "Slack integration", "CSV export"] do
        {:ok, _} = Events.answer_poll(event, new_participant.(), poll, option)
      end

      event

    existing ->
      existing
  end

IO.puts("""

Seeded demo presenter:
  email:    #{demo_email}
  password: demo-password-please-change

Sample event "#{event.title}" (join code #{event.join_code}) created (or already present).
""")
