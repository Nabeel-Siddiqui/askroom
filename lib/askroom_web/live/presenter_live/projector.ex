defmodule AskroomWeb.PresenterLive.Projector do
  @moduledoc """
  A full-screen, large-text page meant for a projector or a shared
  screen at the venue: whichever is more relevant right now. A live poll
  takes over the whole screen with its results while it's running;
  otherwise the top questions by vote are shown. No manual toggle is
  needed — the same `:poll_launched`/`:poll_closed` broadcasts
  `AskroomWeb.PresenterLive.Show` reacts to just switch this page's mode
  automatically.
  """

  use AskroomWeb, :live_view

  alias Askroom.Events

  @top_questions_limit 5

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    presenter = socket.assigns.current_presenter

    case Events.get_event(presenter, id) do
      {:ok, event} ->
        if connected?(socket), do: Events.subscribe(event)

        {:ok,
         socket
         |> assign(:page_title, "#{event.title} — projector")
         |> assign(:event, event)
         |> assign(:top_questions, top_questions(event))
         |> show_poll(Events.current_live_poll(event))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That event doesn't exist.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_info({:question_created, _question}, socket),
    do: {:noreply, refresh_questions(socket)}

  def handle_info({:question_voted, _question}, socket), do: {:noreply, refresh_questions(socket)}

  def handle_info({:question_status_changed, _question}, socket) do
    {:noreply, refresh_questions(socket)}
  end

  def handle_info({:poll_launched, poll}, socket), do: {:noreply, show_poll(socket, poll)}

  def handle_info({:poll_closed, poll}, socket) do
    if socket.assigns.live_poll && socket.assigns.live_poll.id == poll.id do
      {:noreply, socket |> show_poll(nil) |> refresh_questions()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:poll_answered, poll_id}, socket) do
    if socket.assigns.live_poll && socket.assigns.live_poll.id == poll_id do
      {:noreply, assign(socket, :poll_results, Events.poll_results(socket.assigns.live_poll))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp refresh_questions(socket),
    do: assign(socket, :top_questions, top_questions(socket.assigns.event))

  defp top_questions(event),
    do: event |> Events.list_questions() |> Enum.take(@top_questions_limit)

  defp show_poll(socket, nil) do
    socket |> assign(:live_poll, nil) |> assign(:poll_results, [])
  end

  defp show_poll(socket, %Events.Poll{} = poll) do
    socket |> assign(:live_poll, poll) |> assign(:poll_results, Events.poll_results(poll))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-6 py-12">
      <h1 class="text-center text-3xl font-bold text-zinc-900">{@event.title}</h1>

      <div :if={@live_poll} class="mt-12">
        <p class="text-center text-2xl font-semibold text-zinc-900">{@live_poll.question_text}</p>

        <div class="mx-auto mt-10 max-w-2xl space-y-6">
          <div :for={{option, count} <- @poll_results}>
            <div class="flex items-baseline justify-between text-xl text-zinc-900">
              <span>{option}</span>
              <span class="font-bold">{count}</span>
            </div>
            <div class="mt-2 h-6 rounded bg-zinc-100">
              <div
                class="h-6 rounded bg-zinc-900"
                style={"width: #{projector_bar_width(count, @poll_results)}%"}
              />
            </div>
          </div>
        </div>
      </div>

      <div :if={!@live_poll} class="mt-12">
        <ol class="mx-auto max-w-2xl space-y-4">
          <li
            :for={question <- @top_questions}
            class="flex items-center justify-between gap-6 rounded-lg border border-zinc-200 p-5"
          >
            <span class="text-xl text-zinc-900">{question.body}</span>
            <span class="shrink-0 text-2xl font-bold text-zinc-900">{question.vote_count}</span>
          </li>
        </ol>

        <p :if={@top_questions == []} class="mt-12 text-center text-xl text-zinc-400">
          No questions yet
        </p>
      </div>
    </div>
    """
  end

  defp projector_bar_width(_count, []), do: 0

  defp projector_bar_width(count, results) do
    max = results |> Enum.map(&elem(&1, 1)) |> Enum.max()
    if max == 0, do: 0, else: round(count / max * 100)
  end
end
