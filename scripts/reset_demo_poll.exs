# Used by scripts/record_demo (via `mix run`), not meant to be run by
# hand. Resets the seeded demo event's live poll back to its original
# baseline (2 votes for "Slack integration", 1 for "CSV export", 0 for
# "Word cloud") so every recording starts from the same state and the
# GIF always shows the same clear, visible jump — "Word cloud" going
# from an empty bar to its first vote live on the projector.

import Ecto.Query

alias Askroom.Events
alias Askroom.Events.{Event, Poll, PollAnswer}
alias Askroom.Repo

event = Repo.get_by!(Event, title: "Askroom demo talk")
poll = Repo.get_by!(Poll, event_id: event.id, question_text: "Which feature should we build next?")

PollAnswer |> where(poll_id: ^poll.id) |> Repo.delete_all()

for option <- ["Slack integration", "Slack integration", "CSV export"] do
  {:ok, participant} = Events.create_participant(event)
  {:ok, _} = Events.answer_poll(event, participant, poll, option)
end

IO.puts("event id: #{event.id}")
IO.puts("join code: #{event.join_code}")
