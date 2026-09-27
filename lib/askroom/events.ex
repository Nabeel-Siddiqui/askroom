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
  alias Askroom.Events.{Event, Participant, Poll, Question, Vote}
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

  @doc "Fetches an event by id, scoped to `presenter`."
  @spec get_event(Presenter.t(), term()) :: {:ok, Event.t()} | {:error, :not_found}
  def get_event(%Presenter{} = presenter, id) do
    Event
    |> where([e], e.presenter_id == ^presenter.id and e.id == ^id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      event -> {:ok, event}
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

  defp broadcast(%Event{id: event_id}, message), do: broadcast(event_id, message)

  defp broadcast(event_id, message) do
    Phoenix.PubSub.broadcast(Askroom.PubSub, topic(event_id), message)
  end

  defp topic(event_id), do: "event:#{event_id}"
end
