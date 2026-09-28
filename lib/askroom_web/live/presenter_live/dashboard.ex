defmodule AskroomWeb.PresenterLive.Dashboard do
  @moduledoc """
  A presenter's home: create events, open/close them, and jump into
  managing one. `:current_presenter` is assigned by
  `AskroomWeb.PresenterAuth`'s `on_mount` hook.
  """

  use AskroomWeb, :live_view

  alias Askroom.Events

  @impl true
  def mount(_params, _session, socket) do
    presenter = socket.assigns.current_presenter

    {:ok,
     socket
     |> assign(:page_title, "Your events")
     |> assign(:event_form, to_form(%{"title" => ""}, as: "event"))
     |> assign(:events, Events.list_events(presenter))}
  end

  @impl true
  def handle_event("create_event", %{"event" => params}, socket) do
    case Events.create_event(socket.assigns.current_presenter, params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> assign(:event_form, to_form(%{"title" => ""}, as: "event"))
         |> assign(:events, [event | socket.assigns.events])}

      {:error, changeset} ->
        {:noreply, assign(socket, :event_form, to_form(changeset, as: "event"))}
    end
  end

  @impl true
  def handle_event("toggle_status", %{"id" => id}, socket) do
    presenter = socket.assigns.current_presenter

    with {:ok, event} <- Events.get_event(presenter, id),
         {:ok, updated} <- flip_status(presenter, event) do
      {:noreply, replace_event(socket, updated)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp flip_status(presenter, %{status: :open} = event), do: Events.close_event(presenter, event)
  defp flip_status(presenter, %{status: :closed} = event), do: Events.open_event(presenter, event)

  defp replace_event(socket, updated) do
    events = Enum.map(socket.assigns.events, &if(&1.id == updated.id, do: updated, else: &1))
    assign(socket, :events, events)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>Your events</.header>

      <.simple_form for={@event_form} phx-submit="create_event" class="mt-6">
        <.input field={@event_form[:title]} type="text" label="New event title" />
        <:actions>
          <.button phx-disable-with="Creating...">Create event</.button>
        </:actions>
      </.simple_form>

      <ul class="mt-8 divide-y divide-zinc-100">
        <li :for={event <- @events} class="flex items-center justify-between gap-4 py-4">
          <div class="min-w-0">
            <.link
              navigate={~p"/dashboard/events/#{event.id}"}
              class="font-semibold text-zinc-900 hover:underline"
            >
              {event.title}
            </.link>
            <p class="text-sm text-zinc-500">
              Code: <span class="font-mono">{event.join_code}</span>
              ·
              <span class={(event.status == :open && "text-green-700") || "text-zinc-500"}>
                {event.status}
              </span>
            </p>
          </div>

          <button
            type="button"
            phx-click="toggle_status"
            phx-value-id={event.id}
            class="shrink-0 rounded-lg border border-zinc-300 px-3 py-1.5 text-sm font-semibold text-zinc-700 hover:border-zinc-900"
          >
            {if event.status == :open, do: "Close", else: "Reopen"}
          </button>
        </li>
      </ul>

      <p :if={@events == []} class="mt-8 text-center text-sm text-zinc-500">
        No events yet — create your first one above.
      </p>
    </div>
    """
  end
end
