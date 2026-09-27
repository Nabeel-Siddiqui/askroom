defmodule AskroomWeb.JoinControllerTest do
  use AskroomWeb.ConnCase, async: true

  import Askroom.EventsFixtures

  alias Askroom.Events
  alias AskroomWeb.ParticipantAuth

  describe "GET /join" do
    test "renders the join form", %{conn: conn} do
      conn = get(conn, ~p"/join")
      assert html_response(conn, 200) =~ "Join an event"
    end
  end

  describe "POST /join" do
    test "with a valid code, joins and redirects to the event", %{conn: conn} do
      event = event_fixture()

      conn = post(conn, ~p"/join", join_code: event.join_code)

      assert redirected_to(conn) == ~p"/e/#{event.join_code}"
      assert get_session(conn, ParticipantAuth.session_key(event))
    end

    test "is case-insensitive", %{conn: conn} do
      event = event_fixture()

      conn = post(conn, ~p"/join", join_code: String.downcase(event.join_code))

      assert redirected_to(conn) == ~p"/e/#{event.join_code}"
    end

    test "reuses the same participant across repeated joins", %{conn: conn} do
      event = event_fixture()

      conn = post(conn, ~p"/join", join_code: event.join_code)
      first_id = get_session(conn, ParticipantAuth.session_key(event))

      conn = post(conn, ~p"/join", join_code: event.join_code)
      second_id = get_session(conn, ParticipantAuth.session_key(event))

      assert first_id == second_id
      assert Askroom.Repo.aggregate(Askroom.Events.Participant, :count) == 1
    end

    test "with an unknown code, redirects to /join with a flash", %{conn: conn} do
      conn = post(conn, ~p"/join", join_code: "ZZZZZZ")

      assert redirected_to(conn) == ~p"/join"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "doesn't match"
    end
  end

  describe "GET /join/:code" do
    test "with a valid code, joins and redirects to the event", %{conn: conn} do
      event = event_fixture()

      conn = get(conn, ~p"/join/#{event.join_code}")

      assert redirected_to(conn) == ~p"/e/#{event.join_code}"
      assert get_session(conn, ParticipantAuth.session_key(event))
    end

    test "with an unknown code, redirects to /join with a flash", %{conn: conn} do
      conn = get(conn, ~p"/join/ZZZZZZ")

      assert redirected_to(conn) == ~p"/join"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "doesn't match"
    end
  end

  describe "ParticipantAuth.ensure_participant/2 re-validation" do
    test "mints a fresh participant if the session points at one from a different event", %{
      conn: conn
    } do
      event_a = event_fixture()
      event_b = event_fixture()
      {conn, participant_a} = join_as_participant(conn, event_a)

      # Simulate the session somehow holding event_a's participant id
      # under event_b's key (e.g. a stale/tampered cookie).
      conn = put_session(conn, ParticipantAuth.session_key(event_b), participant_a.id)

      conn = ParticipantAuth.ensure_participant(conn, event_b)
      new_id = get_session(conn, ParticipantAuth.session_key(event_b))

      assert new_id != participant_a.id
      assert {:ok, _} = Events.get_participant(event_b, new_id)
    end
  end
end
