defmodule AskroomWeb.JoinController do
  @moduledoc """
  The audience join flow: entering a code, or opening a `/join/:code`
  link, establishes an anonymous participant and lands on the event's
  live page.

  This has to be a plain controller, not a LiveView — establishing the
  participant means writing to the plug session, and a LiveView process
  has no `conn` to write a session cookie through once its socket is
  live. `AskroomWeb.ParticipantAuth.ensure_participant/2` does that
  write; the resulting live page then just reads the session value
  `on_mount`.
  """

  use AskroomWeb, :controller

  alias Askroom.Events
  alias AskroomWeb.ParticipantAuth

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"join_code" => code}) do
    do_join(conn, code, redirect_on_error: ~p"/join")
  end

  def join(conn, %{"code" => code}) do
    do_join(conn, code, redirect_on_error: ~p"/join")
  end

  defp do_join(conn, code, redirect_on_error: error_path) do
    case Events.get_event_by_join_code(code) do
      {:ok, event} ->
        conn
        |> ParticipantAuth.ensure_participant(event)
        |> redirect(to: ~p"/e/#{event.join_code}")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "That code doesn't match any event.")
        |> redirect(to: error_path)
    end
  end
end
