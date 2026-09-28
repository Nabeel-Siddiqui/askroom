defmodule AskroomWeb.AudienceLive do
  @moduledoc """
  The mobile-first page an audience member lands on after joining: ask a
  question, upvote others, answer whatever poll is currently live, watch
  all three update as the rest of the audience does the same.

  `:event` and `:current_participant` are assigned by
  `AskroomWeb.ParticipantAuth`'s `on_mount` hook before this module's own
  `mount/3` runs.

  Every write here (submitting a question, toggling a vote, answering a
  poll) only calls `Askroom.Events` and never touches the stream or
  other derived assigns directly — the single place those actually
  change is `handle_info/2`, reacting to the same
  `Askroom.Events.subscribe/1` broadcast every other participant's
  screen reacts to, including this one's own action circling back to it.
  That keeps "what does this participant see" defined once, the same way
  regardless of whether the underlying change came from this browser tab
  or someone else's.
  """

  use AskroomWeb, :live_view

  alias Askroom.Events
  alias AskroomWeb.Presence

  @impl true
  def mount(_params, _session, socket) do
    event = socket.assigns.event
    participant = socket.assigns.current_participant

    if connected?(socket) do
      Events.subscribe(event)
      Presence.track(self(), Events.presence_topic(event), participant.id, %{})
    end

    questions = Events.list_questions(event)

    {:ok,
     socket
     |> assign(:page_title, event.title)
     |> assign(:question_form, to_form(%{"body" => ""}, as: "question"))
     |> assign(:voted_question_ids, Events.voted_question_ids(participant))
     |> assign(:any_questions?, questions != [])
     |> assign(:event_closed?, event.status == :closed)
     |> assign_current_poll(Events.current_live_poll(event))
     |> stream(:questions, questions)}
  end

  @impl true
  def handle_event("submit_question", %{"question" => params}, socket) do
    case Events.create_question(socket.assigns.event, socket.assigns.current_participant, params) do
      {:ok, _question} ->
        {:noreply, assign(socket, :question_form, to_form(%{"body" => ""}, as: "question"))}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(socket, :error, "You're posting a little fast — try again in a few seconds.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :question_form, to_form(changeset, as: "question"))}
    end
  end

  @impl true
  def handle_event("toggle_vote", %{"id" => id}, socket) do
    with {:ok, question} <- Events.get_question(socket.assigns.event, id) do
      Events.toggle_vote(socket.assigns.current_participant, question)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("answer_poll", %{"option" => option}, socket) do
    if poll = socket.assigns.current_poll do
      Events.answer_poll(socket.assigns.event, socket.assigns.current_participant, poll, option)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:question_created, _question}, socket) do
    {:noreply, refresh_questions(socket)}
  end

  def handle_info({:question_voted, _question}, socket) do
    {:noreply, refresh_questions(socket)}
  end

  def handle_info({:question_status_changed, _question}, socket) do
    {:noreply, refresh_questions(socket)}
  end

  def handle_info({:poll_launched, poll}, socket) do
    {:noreply, assign_current_poll(socket, poll)}
  end

  def handle_info({:poll_closed, poll}, socket) do
    if socket.assigns.current_poll && socket.assigns.current_poll.id == poll.id do
      {:noreply, assign_current_poll(socket, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:poll_answered, poll_id}, socket) do
    # This is how *this participant's own* answer gets its "recorded"
    # confirmation to show — not a results update (this page never shows
    # tallies, only the presenter/projector do). Without reacting to
    # this broadcast at all, poll_answered? would only ever be set at
    # mount or when a new poll launches, so answering a poll would
    # silently never show any confirmation.
    if socket.assigns.current_poll && socket.assigns.current_poll.id == poll_id do
      answered? =
        Events.answered_poll?(socket.assigns.current_participant, socket.assigns.current_poll)

      {:noreply, assign(socket, :poll_answered?, answered?)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:event_closed, event}, socket) do
    {:noreply, socket |> assign(event: event, event_closed?: true) |> refresh_questions()}
  end

  def handle_info({:event_reopened, event}, socket) do
    {:noreply, socket |> assign(event: event, event_closed?: false) |> refresh_questions()}
  end

  # Presence's own "presence_diff" broadcasts arrive on the same
  # subscription — irrelevant here, since this page doesn't display a
  # participant count (only the presenter's dashboard does).
  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_current_poll(socket, nil) do
    socket |> assign(:current_poll, nil) |> assign(:poll_answered?, false)
  end

  defp assign_current_poll(socket, %Events.Poll{} = poll) do
    answered? = Events.answered_poll?(socket.assigns.current_participant, poll)
    socket |> assign(:current_poll, poll) |> assign(:poll_answered?, answered?)
  end

  # A full requery-and-reset, rather than patching the one changed
  # question in place, because a vote can change the *sort order* (votes
  # desc, then newest) — a stream can cheaply update or insert one item,
  # but re-sorting the whole list is exactly what a fresh, correctly
  # ordered query already gives us. At this app's scale (one talk's
  # audience, not a firehose), requerying on every change is simple and
  # fast enough that it isn't worth hand-tracking positions instead.
  defp refresh_questions(socket) do
    questions = Events.list_questions(socket.assigns.event)

    socket
    |> assign(:voted_question_ids, Events.voted_question_ids(socket.assigns.current_participant))
    |> assign(:any_questions?, questions != [])
    |> stream(:questions, questions, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md">
      <h1 class="text-xl font-bold text-zinc-900">{@event.title}</h1>

      <div
        :if={@event_closed?}
        class="mt-4 rounded-lg bg-zinc-100 p-4 text-center text-sm text-zinc-600"
      >
        This event has ended. Thanks for participating!
      </div>

      <div :if={@current_poll && !@event_closed?} class="mt-4 rounded-lg border border-zinc-900 p-4">
        <p class="font-semibold text-zinc-900">{@current_poll.question_text}</p>

        <div :if={!@poll_answered?} class="mt-3 space-y-2">
          <button
            :for={option <- @current_poll.options}
            type="button"
            phx-click="answer_poll"
            phx-value-option={option}
            class="w-full rounded-lg border border-zinc-300 px-4 py-2 text-left text-sm text-zinc-900 hover:border-zinc-900"
          >
            {option}
          </button>
        </div>

        <p :if={@poll_answered?} class="mt-3 text-sm text-zinc-600">
          Thanks — your answer's been recorded.
        </p>
      </div>

      <.simple_form
        :if={!@event_closed?}
        for={@question_form}
        phx-submit="submit_question"
        class="mt-6"
      >
        <.input
          field={@question_form[:body]}
          type="text"
          placeholder="Ask a question..."
          maxlength="280"
        />
        <:actions>
          <.button class="w-full" phx-disable-with="Sending...">Send</.button>
        </:actions>
      </.simple_form>

      <ul id="questions" phx-update="stream" class="mt-6 space-y-3">
        <li
          :for={{dom_id, question} <- @streams.questions}
          id={dom_id}
          class="flex items-start justify-between gap-3 rounded-lg border border-zinc-200 p-4"
        >
          <div class="min-w-0">
            <p class="break-words text-sm text-zinc-900">{question.body}</p>
            <p :if={question.status == :answered} class="mt-1 text-xs font-medium text-green-700">
              Answered
            </p>
          </div>

          <button
            type="button"
            phx-click="toggle_vote"
            phx-value-id={question.id}
            disabled={@event_closed?}
            class={[
              "flex shrink-0 flex-col items-center rounded-lg border px-3 py-2 text-sm font-semibold",
              MapSet.member?(@voted_question_ids, question.id) &&
                "border-zinc-900 bg-zinc-900 text-white",
              !MapSet.member?(@voted_question_ids, question.id) &&
                "border-zinc-300 text-zinc-700 hover:border-zinc-900"
            ]}
          >
            <span aria-hidden="true">&uarr;</span>
            <span>{question.vote_count}</span>
          </button>
        </li>
      </ul>

      <p :if={!@any_questions?} class="mt-6 text-center text-sm text-zinc-500">
        No questions yet — be the first to ask one.
      </p>
    </div>
    """
  end
end
