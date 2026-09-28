defmodule AskroomWeb.PresenterLive.Show do
  @moduledoc """
  A presenter's control panel for one event: the join QR code, how many
  people are currently in the room, the moderation queue, and polls.

  Every action that has an audience (opening/closing the event,
  moderation, launching/closing a poll) only calls `Askroom.Events` and
  lets the resulting broadcast — the same one every audience member's
  screen reacts to — come back through `handle_info/2` to actually
  update this page's assigns, exactly like `AskroomWeb.AudienceLive`.
  Poll *creation* is the one exception: a freshly created poll is a
  draft nobody but this presenter can see yet, so there's nothing to
  broadcast, and `handle_event/3` updates the `:polls` assign directly —
  the same as `AskroomWeb.PresenterLive.Dashboard` does for creating an
  event.
  """

  use AskroomWeb, :live_view

  alias Askroom.Events
  alias AskroomWeb.Presence

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    presenter = socket.assigns.current_presenter

    case Events.get_event(presenter, id) do
      {:ok, event} ->
        if connected?(socket), do: Events.subscribe(event)

        displayed_poll = Events.current_live_poll(event) || List.first(Events.list_polls(event))

        {:ok,
         socket
         |> assign(:page_title, event.title)
         |> assign(:event, event)
         |> assign(:poll_form, to_form(%{"question_text" => "", "options" => ""}, as: "poll"))
         |> assign(:questions, Events.list_questions_for_presenter(event))
         |> assign(:polls, Events.list_polls(event))
         |> assign(:presence_count, Presence.list(Events.presence_topic(event)) |> map_size())
         |> show_poll(displayed_poll)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That event doesn't exist.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("toggle_status", _params, socket) do
    presenter = socket.assigns.current_presenter
    event = socket.assigns.event

    if event.status == :open do
      Events.close_event(presenter, event)
    else
      Events.open_event(presenter, event)
    end

    {:noreply, socket}
  end

  def handle_event("approve_question", %{"id" => id}, socket),
    do: moderate(socket, id, &Events.approve_question/3)

  def handle_event("mark_answered", %{"id" => id}, socket),
    do: moderate(socket, id, &Events.mark_question_answered/3)

  def handle_event("hide_question", %{"id" => id}, socket),
    do: moderate(socket, id, &Events.hide_question/3)

  def handle_event("create_poll", %{"poll" => params}, socket) do
    params = Map.update(params, "options", [], &split_options/1)

    case Events.create_poll(socket.assigns.current_presenter, socket.assigns.event, params) do
      {:ok, poll} ->
        {:noreply,
         socket
         |> assign(:poll_form, to_form(%{"question_text" => "", "options" => ""}, as: "poll"))
         |> assign(:polls, [poll | socket.assigns.polls])}

      {:error, changeset} ->
        {:noreply, assign(socket, :poll_form, to_form(changeset, as: "poll"))}
    end
  end

  def handle_event("launch_poll", %{"id" => id}, socket) do
    with {:ok, poll} <- Events.get_poll(socket.assigns.event, id) do
      Events.launch_poll(socket.assigns.current_presenter, socket.assigns.event, poll)
    end

    {:noreply, socket}
  end

  def handle_event("close_poll", %{"id" => id}, socket) do
    with {:ok, poll} <- Events.get_poll(socket.assigns.event, id) do
      Events.close_poll(socket.assigns.current_presenter, socket.assigns.event, poll)
    end

    {:noreply, socket}
  end

  defp moderate(socket, id, fun) do
    presenter = socket.assigns.current_presenter
    event = socket.assigns.event

    with {:ok, question} <- Events.get_question(event, id) do
      fun.(presenter, event, question)
    end

    {:noreply, socket}
  end

  defp split_options(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @impl true
  def handle_info({:question_created, _question}, socket),
    do: {:noreply, refresh_questions(socket)}

  def handle_info({:question_voted, _question}, socket), do: {:noreply, refresh_questions(socket)}

  def handle_info({:question_status_changed, _question}, socket) do
    {:noreply, refresh_questions(socket)}
  end

  def handle_info({:event_closed, event}, socket), do: {:noreply, assign(socket, :event, event)}
  def handle_info({:event_reopened, event}, socket), do: {:noreply, assign(socket, :event, event)}

  def handle_info({:poll_launched, poll}, socket), do: {:noreply, show_poll(socket, poll)}
  def handle_info({:poll_closed, poll}, socket), do: {:noreply, show_poll(socket, poll)}

  def handle_info({:poll_answered, poll_id}, socket) do
    if socket.assigns.displayed_poll && socket.assigns.displayed_poll.id == poll_id do
      {:noreply,
       assign(socket, :poll_results, Events.poll_results(socket.assigns.displayed_poll))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    count = Presence.list(Events.presence_topic(socket.assigns.event)) |> map_size()
    {:noreply, assign(socket, :presence_count, count)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp refresh_questions(socket) do
    assign(socket, :questions, Events.list_questions_for_presenter(socket.assigns.event))
  end

  defp show_poll(socket, nil) do
    socket |> assign(:displayed_poll, nil) |> assign(:poll_results, [])
  end

  defp show_poll(socket, %Events.Poll{} = poll) do
    socket
    |> assign(:displayed_poll, poll)
    |> assign(:poll_results, Events.poll_results(poll))
    |> assign(:polls, Events.list_polls(socket.assigns.event))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl space-y-10">
      <div>
        <.header>
          {@event.title}
          <:subtitle>
            Join at <span class="font-mono">{url(~p"/join/#{@event.join_code}")}</span>
            · {@presence_count} {ngettext("person", "people", @presence_count)} here now
          </:subtitle>
          <:actions>
            <.link
              navigate={~p"/dashboard/events/#{@event.id}/projector"}
              class="rounded-lg border border-zinc-300 px-3 py-1.5 text-sm font-semibold text-zinc-700 hover:border-zinc-900"
            >
              Projector view
            </.link>
            <button
              type="button"
              phx-click="toggle_status"
              class="rounded-lg border border-zinc-300 px-3 py-1.5 text-sm font-semibold text-zinc-700 hover:border-zinc-900"
            >
              {if @event.status == :open, do: "Close event", else: "Reopen event"}
            </button>
          </:actions>
        </.header>

        <div class="mt-4 inline-block rounded-lg border border-zinc-200 p-3">
          {raw(EQRCode.encode(url(~p"/join/#{@event.join_code}")) |> EQRCode.svg(width: 160))}
        </div>
      </div>

      <div>
        <h2 class="text-lg font-semibold text-zinc-900">Questions</h2>

        <ul class="mt-3 divide-y divide-zinc-100">
          <li :for={question <- @questions} class="flex items-center justify-between gap-4 py-3">
            <div class="min-w-0">
              <p class="text-sm text-zinc-900">{question.body}</p>
              <p class="text-xs text-zinc-500">{question.vote_count} votes · {question.status}</p>
            </div>

            <div class="flex shrink-0 gap-2">
              <button
                :if={question.status == :pending}
                type="button"
                phx-click="approve_question"
                phx-value-id={question.id}
                class="rounded-lg border border-zinc-300 px-2 py-1 text-xs font-semibold text-zinc-700 hover:border-zinc-900"
              >
                Approve
              </button>
              <button
                :if={question.status in [:visible, :answered]}
                type="button"
                phx-click="mark_answered"
                phx-value-id={question.id}
                class="rounded-lg border border-zinc-300 px-2 py-1 text-xs font-semibold text-zinc-700 hover:border-zinc-900"
              >
                Mark answered
              </button>
              <button
                type="button"
                phx-click="hide_question"
                phx-value-id={question.id}
                class="rounded-lg border border-zinc-300 px-2 py-1 text-xs font-semibold text-zinc-700 hover:border-zinc-900"
              >
                Hide
              </button>
            </div>
          </li>
        </ul>

        <p :if={@questions == []} class="mt-3 text-sm text-zinc-500">No questions yet.</p>
      </div>

      <div>
        <h2 class="text-lg font-semibold text-zinc-900">Polls</h2>

        <.simple_form for={@poll_form} phx-submit="create_poll" class="mt-3">
          <.input field={@poll_form[:question_text]} type="text" label="Question" />
          <.input
            field={@poll_form[:options]}
            type="textarea"
            label="Options (one per line)"
            placeholder="Option A\nOption B"
          />
          <:actions>
            <.button phx-disable-with="Creating...">Create poll</.button>
          </:actions>
        </.simple_form>

        <ul class="mt-4 space-y-3">
          <li :for={poll <- @polls} class="rounded-lg border border-zinc-200 p-3">
            <div class="flex items-center justify-between gap-3">
              <p class="text-sm font-semibold text-zinc-900">{poll.question_text}</p>

              <button
                :if={poll.status == :draft}
                type="button"
                phx-click="launch_poll"
                phx-value-id={poll.id}
                class="shrink-0 rounded-lg bg-zinc-900 px-3 py-1 text-xs font-semibold text-white"
              >
                Launch
              </button>
              <button
                :if={poll.status == :live}
                type="button"
                phx-click="close_poll"
                phx-value-id={poll.id}
                class="shrink-0 rounded-lg border border-zinc-300 px-3 py-1 text-xs font-semibold text-zinc-700"
              >
                Close
              </button>
              <span :if={poll.status == :closed} class="shrink-0 text-xs text-zinc-500">Closed</span>
            </div>

            <div :if={@displayed_poll && @displayed_poll.id == poll.id} class="mt-3 space-y-1.5">
              <.poll_result_bar
                :for={{option, count} <- @poll_results}
                option={option}
                count={count}
                max={max_count(@poll_results)}
              />
            </div>
          </li>
        </ul>

        <p :if={@polls == []} class="mt-3 text-sm text-zinc-500">No polls yet.</p>
      </div>
    </div>
    """
  end

  attr :option, :string, required: true
  attr :count, :integer, required: true
  attr :max, :integer, required: true

  defp poll_result_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-sm">
      <span class="w-28 shrink-0 truncate text-zinc-700">{@option}</span>
      <div class="h-4 flex-1 rounded bg-zinc-100">
        <div class="h-4 rounded bg-zinc-900" style={"width: #{bar_width(@count, @max)}%"} />
      </div>
      <span class="w-6 shrink-0 text-right text-zinc-500">{@count}</span>
    </div>
    """
  end

  defp bar_width(_count, 0), do: 0
  defp bar_width(count, max), do: round(count / max * 100)

  defp max_count([]), do: 0
  defp max_count(results), do: results |> Enum.map(&elem(&1, 1)) |> Enum.max()
end
