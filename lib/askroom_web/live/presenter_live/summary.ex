defmodule AskroomWeb.PresenterLive.Summary do
  @moduledoc """
  The wrap-up view for a closed event: every question that made it to
  the audience, ranked by votes, and the final results of every poll
  that ran. A static snapshot, not a live page — unlike
  `AskroomWeb.PresenterLive.Show`, there's no PubSub subscription here,
  since a summary is meant to be read after the fact, not watched update
  in real time.
  """

  use AskroomWeb, :live_view

  alias Askroom.Events

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    presenter = socket.assigns.current_presenter

    case Events.get_event(presenter, id) do
      {:ok, event} ->
        polls = event |> Events.list_polls() |> Enum.reject(&(&1.status == :draft))

        {:ok,
         socket
         |> assign(:page_title, "#{event.title} — summary")
         |> assign(:event, event)
         |> assign(:questions, Events.list_questions(event))
         |> assign(:polls, Enum.map(polls, &{&1, Events.poll_results(&1)}))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That event doesn't exist.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl space-y-10">
      <.header>
        {@event.title}
        <:subtitle>Event summary · {@event.status}</:subtitle>
        <:actions>
          <.link
            navigate={~p"/dashboard/events/#{@event.id}"}
            class="rounded-lg border border-zinc-300 px-3 py-1.5 text-sm font-semibold text-zinc-700 hover:border-zinc-900"
          >
            Back to event
          </.link>
        </:actions>
      </.header>

      <div>
        <h2 class="text-lg font-semibold text-zinc-900">Top questions</h2>

        <ol class="mt-3 space-y-2">
          <li
            :for={question <- @questions}
            class="flex items-center justify-between gap-4 rounded-lg border border-zinc-200 p-3"
          >
            <span class="text-sm text-zinc-900">{question.body}</span>
            <span class="shrink-0 text-sm font-semibold text-zinc-500">
              {question.vote_count} votes
            </span>
          </li>
        </ol>

        <p :if={@questions == []} class="mt-3 text-sm text-zinc-500">No questions were asked.</p>
      </div>

      <div>
        <h2 class="text-lg font-semibold text-zinc-900">Poll results</h2>

        <div :for={{poll, results} <- @polls} class="mt-4 rounded-lg border border-zinc-200 p-4">
          <p class="text-sm font-semibold text-zinc-900">{poll.question_text}</p>

          <div class="mt-2 space-y-1 text-sm text-zinc-700">
            <div :for={{option, count} <- results} class="flex justify-between">
              <span>{option}</span>
              <span class="font-semibold">{count}</span>
            </div>
          </div>
        </div>

        <p :if={@polls == []} class="mt-3 text-sm text-zinc-500">No polls were run.</p>
      </div>
    </div>
    """
  end
end
