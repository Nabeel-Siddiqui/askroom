defmodule AskroomWeb.PresenterLive.EventScope do
  @moduledoc """
  An `on_mount` hook shared by every `/dashboard/events/:id/...` route
  (`PresenterLive.Show`, `.Projector`, `.Summary`): loads the `:id`
  param's event, scoped to the current presenter, and assigns it as
  `:event` before that LiveView's own `mount/3` runs.

  All three pages used to repeat the identical
  `{:error, :not_found} -> flash + redirect to the dashboard` branch;
  this is the one place that's written now, so each page's own mount/3
  only has to handle what's actually different about it.
  """

  use AskroomWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias Askroom.Events

  def on_mount(:assign_event, %{"id" => id}, _session, socket) do
    presenter = socket.assigns.current_presenter

    case Events.get_event(presenter, id) do
      {:ok, event} ->
        {:cont, assign(socket, :event, event)}

      {:error, :not_found} ->
        {:halt,
         socket
         |> put_flash(:error, "That event doesn't exist.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end
end
