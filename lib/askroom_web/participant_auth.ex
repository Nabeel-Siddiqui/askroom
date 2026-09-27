defmodule AskroomWeb.ParticipantAuth do
  @moduledoc """
  Establishes and loads the anonymous audience identity used by the
  join flow and the live event pages.

  A participant is scoped to one event, so the session key is
  namespaced by event id — joining two different events in the same
  browser gets two independent identities, and joining the same event
  twice (e.g. after closing the tab and coming back) resumes the same
  one.

  Session values only ever go in as plain strings and only ever come
  back out through `Askroom.Events.get_participant/2`, which treats a
  malformed or stale value as "no participant" rather than raising —
  the value in a session cookie was written by this app, but a browser
  can hold onto it indefinitely, so it's still treated as untrusted
  input rather than as always corresponding to a live row.
  """

  import Plug.Conn

  alias Askroom.Events
  alias Askroom.Events.Event

  @doc "The session key a participant id for `event` is stored under."
  @spec session_key(Event.t()) :: String.t()
  def session_key(%Event{} = event), do: "participant_id_for_event_#{event.id}"

  @doc """
  Ensures the current session has a participant for `event`: reuses the
  one named in the session if it's still valid, otherwise creates a new
  one and writes it into the session.
  """
  @spec ensure_participant(Plug.Conn.t(), Event.t()) :: Plug.Conn.t()
  def ensure_participant(conn, %Event{} = event) do
    key = session_key(event)

    with id when is_binary(id) <- get_session(conn, key),
         {:ok, _participant} <- Events.get_participant(event, id) do
      conn
    else
      _ ->
        {:ok, participant} = Events.create_participant(event)
        put_session(conn, key, participant.id)
    end
  end

  @doc """
  `on_mount` hook for the audience live pages: loads the event from the
  `:code` path param and the participant from the session, halting with
  a redirect to the join flow if either is missing — which covers both
  "never joined" (no session key at all) and "the session points at a
  participant that no longer resolves" (a stale or tampered value).
  """
  def on_mount(:require_participant, %{"code" => code}, session, socket) do
    with {:ok, event} <- Events.get_event_by_join_code(code),
         id when is_binary(id) <- session[session_key(event)],
         {:ok, participant} <- Events.get_participant(event, id) do
      {:cont,
       socket
       |> Phoenix.Component.assign(:event, event)
       |> Phoenix.Component.assign(:current_participant, participant)}
    else
      _ ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/join/#{code}")}
    end
  end
end
