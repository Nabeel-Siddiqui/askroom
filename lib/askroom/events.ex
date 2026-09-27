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
  alias Askroom.Events.{Event, Participant, Poll, Question}
  alias Askroom.Repo

  @max_join_code_attempts 5

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
  """
  @spec create_question(Event.t(), Participant.t(), map()) ::
          {:ok, Question.t()} | {:error, Ecto.Changeset.t()}
  def create_question(%Event{} = event, %Participant{} = participant, attrs) do
    initial_status = if event.moderation_enabled, do: :pending, else: :visible

    %Question{event_id: event.id, participant_id: participant.id, status: initial_status}
    |> Question.changeset(attrs)
    |> Repo.insert()
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
end
