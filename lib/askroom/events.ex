defmodule Askroom.Events do
  @moduledoc """
  Events, their audience, and the questions/polls exchanged during them.

  Every function that reads or writes an `Event` a presenter doesn't own
  returns `{:error, :not_found}`, not `{:error, :unauthorized}` — a
  presenter who guesses another event's id shouldn't be able to tell the
  difference between "not yours" and "doesn't exist."
  """

  import Ecto.Query, warn: false

  alias Askroom.Accounts.Presenter
  alias Askroom.Events.{Event, Participant, Poll, PollAnswer, Question, Vote}
  alias Askroom.Repo

  @max_join_code_attempts 5
  @question_rate_limit_seconds 10

  @doc """
  Creates an event owned by `presenter`, with a fresh, unique join code.

  Generates the code and attempts the insert directly rather than
  checking uniqueness first — a check-then-insert has its own race
  against a concurrent request minting the same code. On the rare
  collision (astronomically unlikely at this app's scale — the alphabet
  gives roughly a billion 6-character codes) it just tries again, up to
  a handful of times.
  """
  @spec create_event(Presenter.t(), map()) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t() | :join_code_generation_failed}
  def create_event(%Presenter{} = presenter, attrs) do
    do_create_event(presenter, attrs, @max_join_code_attempts)
  end

  defp do_create_event(_presenter, _attrs, 0), do: {:error, :join_code_generation_failed}

  defp do_create_event(presenter, attrs, attempts_left) do
    changeset =
      %Event{presenter_id: presenter.id}
      |> Event.changeset(attrs)
      |> Event.put_join_code()

    case Repo.insert(changeset) do
      {:ok, event} ->
        {:ok, event}

      {:error, changeset} ->
        if Keyword.has_key?(changeset.errors, :join_code) do
          do_create_event(presenter, attrs, attempts_left - 1)
        else
          {:error, changeset}
        end
    end
  end

  @doc """
  Fetches an event by id, scoped to `presenter`. `id` comes straight from
  a route param on `/dashboard/events/:id`, so a non-numeric value is
  treated as not-found rather than raising an `Ecto.Query.CastError`.
  """
  @spec get_event(Presenter.t(), term()) :: {:ok, Event.t()} | {:error, :not_found}
  def get_event(%Presenter{} = presenter, id) do
    with {int_id, ""} <- Integer.parse(to_string(id)),
         %Event{} = event <- Repo.get_by(Event, id: int_id, presenter_id: presenter.id) do
      {:ok, event}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Fetches an event by its join code, for the audience join flow —
  deliberately *not* scoped to a presenter, since anyone with the code
  is meant to find the event. Codes are stored and looked up
  case-normalized, so `"ab3xyz"` and `"AB3XYZ"` reach the same event.
  """
  @spec get_event_by_join_code(String.t()) :: {:ok, Event.t()} | {:error, :not_found}
  def get_event_by_join_code(join_code) when is_binary(join_code) do
    normalized = join_code |> String.trim() |> String.upcase()

    case Repo.get_by(Event, join_code: normalized) do
      nil -> {:error, :not_found}
      event -> {:ok, event}
    end
  end

  @doc "Lists `presenter`'s own events, newest first."
  @spec list_events(Presenter.t()) :: [Event.t()]
  def list_events(%Presenter{} = presenter) do
    Event
    |> where([e], e.presenter_id == ^presenter.id)
    # :id as a tiebreaker matters because inserted_at (utc_datetime) only
    # has second precision — two events created within the same second
    # would otherwise sort nondeterministically.
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> Repo.all()
  end

  @doc "Updates an event, scoped to `presenter`."
  @spec update_event(Presenter.t(), Event.t(), map()) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def update_event(%Presenter{} = presenter, %Event{} = event, attrs) do
    with {:ok, event} <- get_event(presenter, event.id) do
      event
      |> Event.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Reopens a closed event, scoped to `presenter`. Broadcasts
  `:event_reopened` — the symmetric counterpart to `close_event/2`'s
  `:event_closed`, so a participant already on the audience page when a
  presenter reopens sees the "this event has ended" banner clear rather
  than staying stuck once closed.
  """
  @spec open_event(Presenter.t(), Event.t()) :: {:ok, Event.t()} | {:error, :not_found}
  def open_event(%Presenter{} = presenter, %Event{} = event) do
    with {:ok, event} <- get_event(presenter, event.id) do
      {:ok, reopened} = event |> Event.status_changeset(:open) |> Repo.update()
      broadcast(reopened, {:event_reopened, reopened})
      {:ok, reopened}
    end
  end

  @doc """
  Closes an event, scoped to `presenter`. Broadcasts `:event_closed` so
  the audience page can stop accepting new questions/votes and show that
  the event has ended, instead of silently continuing to accept input
  nobody will ever see acted on.
  """
  @spec close_event(Presenter.t(), Event.t()) :: {:ok, Event.t()} | {:error, :not_found}
  def close_event(%Presenter{} = presenter, %Event{} = event) do
    with {:ok, event} <- get_event(presenter, event.id) do
      {:ok, do_close_event(event)}
    end
  end

  defp do_close_event(event) do
    {:ok, closed} = event |> Event.status_changeset(:closed) |> Repo.update()
    broadcast(closed, {:event_closed, closed})
    closed
  end

  @stale_event_hours 24

  @doc """
  Closes every `:open` event that's been running for more than
  #{@stale_event_hours} hours, broadcasting `:event_closed` for each —
  same as a presenter-initiated close, so any participant still on the
  audience page reacts the same way. Called by the nightly Oban cron
  job (`Askroom.Events.CloseStaleEventsWorker`); not exposed as a
  presenter-facing action since it isn't scoped to one presenter — it
  sweeps every presenter's stale events in one pass.
  """
  @spec close_stale_events() :: {:ok, non_neg_integer()}
  def close_stale_events do
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_event_hours * 3600, :second)

    stale_events =
      Event
      |> where([e], e.status == :open and e.inserted_at < ^cutoff)
      |> Repo.all()

    Enum.each(stale_events, &do_close_event/1)

    {:ok, length(stale_events)}
  end

  @doc "Adds an anonymous participant to `event`."
  @spec create_participant(Event.t(), map()) ::
          {:ok, Participant.t()} | {:error, Ecto.Changeset.t()}
  def create_participant(%Event{} = event, attrs \\ %{}) do
    %Participant{event_id: event.id}
    |> Participant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Submits a question from `participant` to `event`. Its initial status
  depends on the event's moderation setting: `:pending` (awaiting a
  presenter's approval) if moderation is enabled, `:visible` (shown to
  the audience immediately) if not.

  A simple per-participant spam guard: rejects with
  `{:error, :rate_limited}` if this participant submitted a question in
  the last #{@question_rate_limit_seconds} seconds, tracked on the
  participant's own row so it survives a page refresh. The claim is a
  single conditional `UPDATE ... WHERE`, not a check against whatever
  `last_question_submitted_at` happens to already be on the `participant`
  struct passed in — that struct can be stale (e.g. across a LiveView
  connection's whole lifetime, if nothing re-fetches it after a previous
  submission), so checking it directly would let the limit silently stop
  doing anything after the first call. This isn't the same
  database-enforced-fairness bar as voting (a burst of a few extra
  questions isn't a correctness bug the way a miscounted vote would be),
  but it's just as cheap to make race-free, so it is.
  """
  @spec create_question(Event.t(), Participant.t(), map()) ::
          {:ok, Question.t()} | {:error, Ecto.Changeset.t() | :rate_limited}
  def create_question(%Event{} = event, %Participant{} = participant, attrs) do
    initial_status = if event.moderation_enabled, do: :pending, else: :visible

    changeset =
      %Question{event_id: event.id, participant_id: participant.id, status: initial_status}
      |> Question.changeset(attrs)

    cond do
      not changeset.valid? ->
        {:error, %{changeset | action: :insert}}

      not claim_question_rate_limit_slot(participant) ->
        {:error, :rate_limited}

      true ->
        {:ok, question} = Repo.insert(changeset)
        broadcast(event, {:question_created, question})
        {:ok, question}
    end
  end

  defp claim_question_rate_limit_slot(%Participant{id: id}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    cutoff = DateTime.add(now, -@question_rate_limit_seconds, :second)

    {count, _} =
      Participant
      |> where([p], p.id == ^id)
      |> where(
        [p],
        is_nil(p.last_question_submitted_at) or p.last_question_submitted_at < ^cutoff
      )
      |> Repo.update_all(set: [last_question_submitted_at: now])

    count == 1
  end

  @doc "Creates a poll for `event`, scoped to `presenter` owning it."
  @spec create_poll(Presenter.t(), Event.t(), map()) ::
          {:ok, Poll.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def create_poll(%Presenter{} = presenter, %Event{} = event, attrs) do
    with {:ok, event} <- get_event(presenter, event.id) do
      %Poll{event_id: event.id}
      |> Poll.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Fetches a poll by id, scoped to `event`. Same defensive non-numeric-id
  handling as `get_question/2`.
  """
  @spec get_poll(Event.t(), term()) :: {:ok, Poll.t()} | {:error, :not_found}
  def get_poll(%Event{} = event, id) do
    with {int_id, ""} <- Integer.parse(to_string(id)),
         %Poll{} = poll <- Repo.get_by(Poll, id: int_id, event_id: event.id) do
      {:ok, poll}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Lists `event`'s polls, newest first."
  @spec list_polls(Event.t()) :: [Poll.t()]
  def list_polls(%Event{} = event) do
    Poll
    |> where([p], p.event_id == ^event.id)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> Repo.all()
  end

  @doc "The currently live poll for `event`, if any."
  @spec current_live_poll(Event.t()) :: Poll.t() | nil
  def current_live_poll(%Event{} = event) do
    Poll
    |> where([p], p.event_id == ^event.id and p.status == :live)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Launches a draft poll, making it live for the audience. Only one poll
  is meant to be live at a time, so this also closes any other poll
  already live for the same event first — a presenter clicking "launch"
  on poll B while poll A is still live almost certainly means "move on
  to B," not "run both at once."
  """
  @spec launch_poll(Presenter.t(), Event.t(), Poll.t()) :: {:ok, Poll.t()} | {:error, :not_found}
  def launch_poll(%Presenter{} = presenter, %Event{} = event, %Poll{} = poll) do
    with {:ok, event} <- get_event(presenter, event.id),
         {:ok, poll} <- get_poll(event, poll.id) do
      Poll
      |> where([p], p.event_id == ^event.id and p.status == :live and p.id != ^poll.id)
      |> Repo.update_all(set: [status: :closed])

      {:ok, launched} = poll |> Poll.status_changeset(:live) |> Repo.update()
      broadcast(event, {:poll_launched, launched})
      {:ok, launched}
    end
  end

  @doc "Closes a live poll, freezing its results."
  @spec close_poll(Presenter.t(), Event.t(), Poll.t()) :: {:ok, Poll.t()} | {:error, :not_found}
  def close_poll(%Presenter{} = presenter, %Event{} = event, %Poll{} = poll) do
    with {:ok, event} <- get_event(presenter, event.id),
         {:ok, poll} <- get_poll(event, poll.id) do
      {:ok, closed} = poll |> Poll.status_changeset(:closed) |> Repo.update()
      broadcast(event, {:poll_closed, closed})
      {:ok, closed}
    end
  end

  @doc """
  Vote counts per option for `poll`, in the poll's own option order —
  ready to feed straight into a bar chart's labels and values, including
  a `0` for any option nobody has chosen yet rather than omitting it.
  """
  @spec poll_results(Poll.t()) :: [{String.t(), non_neg_integer()}]
  def poll_results(%Poll{} = poll) do
    counts =
      PollAnswer
      |> where([a], a.poll_id == ^poll.id)
      |> group_by([a], a.option)
      |> select([a], {a.option, count(a.id)})
      |> Repo.all()
      |> Map.new()

    Enum.map(poll.options, fn option -> {option, Map.get(counts, option, 0)} end)
  end

  @doc "Whether `participant` has already answered `poll`."
  @spec answered_poll?(Participant.t(), Poll.t()) :: boolean()
  def answered_poll?(%Participant{} = participant, %Poll{} = poll) do
    PollAnswer
    |> where([a], a.participant_id == ^participant.id and a.poll_id == ^poll.id)
    |> Repo.exists?()
  end

  @doc """
  Records `participant`'s answer to `poll`. Rejects with
  `{:error, :poll_not_live}` if the poll isn't currently live,
  `{:error, :invalid_option}` if `option` isn't one of the poll's own
  options, or `{:error, :already_answered}` if this participant already
  answered — the same database-enforced, one-per-participant guarantee
  as voting (the unique index on `poll_answers(participant_id, poll_id)`
  is what actually makes this true, this function just turns a violation
  of it into a clean error instead of a raised exception).
  """
  @spec answer_poll(Event.t(), Participant.t(), Poll.t(), String.t()) ::
          {:ok, PollAnswer.t()}
          | {:error, :poll_not_live | :invalid_option | :already_answered | Ecto.Changeset.t()}
  def answer_poll(%Event{} = event, %Participant{} = participant, %Poll{} = poll, option) do
    cond do
      poll.status != :live -> {:error, :poll_not_live}
      option not in poll.options -> {:error, :invalid_option}
      true -> insert_poll_answer(event, participant, poll, option)
    end
  end

  defp insert_poll_answer(event, participant, poll, option) do
    %PollAnswer{}
    |> PollAnswer.changeset(%{option: option, participant_id: participant.id, poll_id: poll.id})
    |> Repo.insert()
    |> case do
      {:ok, answer} ->
        broadcast(event, {:poll_answered, poll.id})
        {:ok, answer}

      {:error, changeset} ->
        classify_poll_answer_error(changeset)
    end
  end

  defp classify_poll_answer_error(changeset) do
    if Keyword.has_key?(changeset.errors, :participant_id) do
      {:error, :already_answered}
    else
      {:error, changeset}
    end
  end

  @doc """
  Fetches a question by id, scoped to `event`. `id` comes straight from
  a `phx-value-id` on the client, so a non-numeric value is treated as
  not-found rather than raising an `Ecto.Query.CastError`.
  """
  @spec get_question(Event.t(), term()) :: {:ok, Question.t()} | {:error, :not_found}
  def get_question(%Event{} = event, id) do
    with {int_id, ""} <- Integer.parse(to_string(id)),
         %Question{} = question <- Repo.get_by(Question, id: int_id, event_id: event.id) do
      {:ok, question}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Lists `event`'s questions for the presenter's moderation view: every
  status except `:hidden`, sorted by vote count then newest. Unlike
  `list_questions/1` (the audience view), this includes `:pending`
  questions awaiting a moderation decision — the whole point of this
  list is to be the place a presenter makes that decision.
  """
  @spec list_questions_for_presenter(Event.t()) :: [Question.t()]
  def list_questions_for_presenter(%Event{} = event) do
    Question
    |> where([q], q.event_id == ^event.id and q.status != :hidden)
    |> order_by([q], desc: q.vote_count, desc: q.inserted_at, desc: q.id)
    |> Repo.all()
  end

  @doc "Approves a pending question, making it visible to the audience."
  @spec approve_question(Presenter.t(), Event.t(), Question.t()) ::
          {:ok, Question.t()} | {:error, :not_found}
  def approve_question(%Presenter{} = presenter, %Event{} = event, %Question{} = question) do
    set_question_status(presenter, event, question, :visible)
  end

  @doc "Marks a question as answered."
  @spec mark_question_answered(Presenter.t(), Event.t(), Question.t()) ::
          {:ok, Question.t()} | {:error, :not_found}
  def mark_question_answered(%Presenter{} = presenter, %Event{} = event, %Question{} = question) do
    set_question_status(presenter, event, question, :answered)
  end

  @doc "Hides a question from the audience."
  @spec hide_question(Presenter.t(), Event.t(), Question.t()) ::
          {:ok, Question.t()} | {:error, :not_found}
  def hide_question(%Presenter{} = presenter, %Event{} = event, %Question{} = question) do
    set_question_status(presenter, event, question, :hidden)
  end

  defp set_question_status(presenter, event, question, status) do
    with {:ok, event} <- get_event(presenter, event.id),
         {:ok, question} <- get_question(event, question.id) do
      {:ok, updated} = question |> Question.status_changeset(status) |> Repo.update()
      broadcast(event, {:question_status_changed, updated})
      {:ok, updated}
    end
  end

  @doc """
  Fetches a participant by id, scoped to `event` — used to re-validate a
  session-stored participant id belongs to the event it's presented for.
  `id` comes straight from a session value that's never been validated,
  so an invalid UUID string is treated the same as a genuine not-found
  rather than raising.
  """
  @spec get_participant(Event.t(), term()) :: {:ok, Participant.t()} | {:error, :not_found}
  def get_participant(%Event{} = event, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Participant{} = participant <- Repo.get_by(Participant, id: uuid, event_id: event.id) do
      {:ok, participant}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Lists `event`'s audience-visible questions — `:visible` or `:answered`
  (`:pending` awaits a presenter's moderation decision, `:hidden` was
  moderated away) — sorted by vote count then newest.
  """
  @spec list_questions(Event.t()) :: [Question.t()]
  def list_questions(%Event{} = event) do
    Question
    |> where([q], q.event_id == ^event.id and q.status in [:visible, :answered])
    # :id as a final tiebreaker for the same reason as list_events/1 —
    # inserted_at is only second-precision.
    |> order_by([q], desc: q.vote_count, desc: q.inserted_at, desc: q.id)
    |> Repo.all()
  end

  @doc "The set of question ids `participant` has voted for, for rendering their upvote buttons active."
  @spec voted_question_ids(Participant.t()) :: MapSet.t(term())
  def voted_question_ids(%Participant{} = participant) do
    Vote
    |> where([v], v.participant_id == ^participant.id)
    |> select([v], v.question_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Toggles `participant`'s vote on `question`: casts it if they haven't
  voted yet, retracts it if they have. Which direction happens is
  decided from the database, inside this same transaction — whether a
  `Vote` row already exists — not from anything the caller believes the
  current state to be, so this is safe to call from a plain toggle
  button with no separate "am I voted" round-trip first.

  `vote_count` is adjusted with `Repo.update_all/2`'s `inc:` option: a
  single `UPDATE questions SET vote_count = vote_count + 1 ...`
  statement, not a read-modify-write from application code. That's what
  keeps the counter correct when many participants vote on the same
  question at the same moment — each increment is applied atomically by
  Postgres itself, so two simultaneous votes can never both read "5" and
  both write "6." The `Vote` row change and the counter adjustment
  happen in the same transaction, so a crash between them can never
  leave the two out of sync.
  """
  @spec toggle_vote(Participant.t(), Question.t()) ::
          {:ok, :voted | :unvoted, Question.t()} | {:error, term()}
  def toggle_vote(%Participant{} = participant, %Question{} = question) do
    Repo.transaction(fn ->
      case Repo.get_by(Vote, participant_id: participant.id, question_id: question.id) do
        nil -> cast_vote(participant, question)
        vote -> retract_vote(vote, question)
      end
    end)
    |> case do
      {:ok, {status, updated_question}} ->
        broadcast(question.event_id, {:question_voted, updated_question})
        {:ok, status, updated_question}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cast_vote(participant, question) do
    %Vote{}
    |> Vote.changeset(%{participant_id: participant.id, question_id: question.id})
    |> Repo.insert()
    |> case do
      {:ok, _vote} -> {:voted, bump_vote_count(question, 1)}
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp retract_vote(vote, question) do
    Repo.delete!(vote)
    {:unvoted, bump_vote_count(question, -1)}
  end

  defp bump_vote_count(question, delta) do
    {1, [updated]} =
      Question
      |> where([q], q.id == ^question.id)
      |> select([q], q)
      |> Repo.update_all(inc: [vote_count: delta])

    updated
  end

  @doc "Subscribes the calling process to `event`'s live updates (new questions, vote changes)."
  @spec subscribe(Event.t()) :: :ok | {:error, term()}
  def subscribe(%Event{} = event) do
    Phoenix.PubSub.subscribe(Askroom.PubSub, topic(event.id))
  end

  @doc """
  The `Phoenix.Presence` topic for `event`'s live participant count —
  deliberately the same string `subscribe/1` uses, so a presenter's
  LiveView (already subscribed for question/poll updates) receives
  Presence's own `"presence_diff"` broadcasts on that same subscription
  for free, with no second topic to track.
  """
  @spec presence_topic(Event.t()) :: String.t()
  def presence_topic(%Event{} = event), do: topic(event.id)

  defp broadcast(%Event{id: event_id}, message), do: broadcast(event_id, message)

  defp broadcast(event_id, message) do
    Phoenix.PubSub.broadcast(Askroom.PubSub, topic(event_id), message)
  end

  defp topic(event_id), do: "event:#{event_id}"
end
