defmodule AskroomWeb.AudienceLiveTest do
  use AskroomWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Askroom.EventsFixtures

  alias Askroom.Events

  describe "mount" do
    test "redirects to the join flow when the visitor has no participant session", %{conn: conn} do
      event = event_fixture()

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/e/#{event.join_code}")
      assert to == "/join/#{event.join_code}"
    end

    test "redirects to the join flow for an unknown event code", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/join/NOPE00"}}} = live(conn, ~p"/e/NOPE00")
    end

    test "renders the event title and an empty state for a joined participant", %{conn: conn} do
      event = event_fixture()
      {conn, _participant} = join_as_participant(conn, event)

      {:ok, _view, html} = live(conn, ~p"/e/#{event.join_code}")

      assert html =~ event.title
      assert html =~ "No questions yet"
    end

    test "shows existing visible questions but not pending or hidden ones", %{conn: conn} do
      event = event_fixture(%{moderation_enabled: true})
      {conn, participant} = join_as_participant(conn, event)

      {:ok, pending} = Events.create_question(event, participant, %{body: "Pending question"})
      visible = pending |> Ecto.Changeset.change(status: :visible) |> Askroom.Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/e/#{event.join_code}")

      assert html =~ visible.body
    end
  end

  describe "submitting a question" do
    test "adds it to the list and clears the form", %{conn: conn} do
      event = event_fixture()
      {conn, _participant} = join_as_participant(conn, event)

      {:ok, view, _html} = live(conn, ~p"/e/#{event.join_code}")

      view
      |> form("form", question: %{body: "What's next for this project?"})
      |> render_submit()

      # The submitter's own screen learns about its new question the
      # same way every other participant's does — via the PubSub
      # broadcast Events.create_question/3 sends, received back here as
      # a handle_info — not from anything handle_event's own return
      # value carries. render_submit/1 only reflects handle_event's
      # synchronous reply, so a second, separate render/1 call is what
      # actually observes the message this view sent to itself.
      assert render(view) =~ "What&#39;s next for this project?"
    end

    test "rejects a blank question with an inline error", %{conn: conn} do
      event = event_fixture()
      {conn, _participant} = join_as_participant(conn, event)

      {:ok, view, _html} = live(conn, ~p"/e/#{event.join_code}")

      html =
        view
        |> form("form", question: %{body: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "rate-limits a rapid second submission with a flash", %{conn: conn} do
      event = event_fixture()
      {conn, _participant} = join_as_participant(conn, event)

      {:ok, view, _html} = live(conn, ~p"/e/#{event.join_code}")

      view |> form("form", question: %{body: "First question"}) |> render_submit()
      html = view |> form("form", question: %{body: "Second question"}) |> render_submit()

      refute html =~ "Second question"
      assert render(view) =~ "posting a little fast"
    end
  end

  describe "toggling a vote" do
    test "casts and retracts a vote, updating the visible count", %{conn: conn} do
      event = event_fixture()
      {conn, _participant} = join_as_participant(conn, event)
      question = question_fixture(event, participant_fixture(event))

      {:ok, view, html} = live(conn, ~p"/e/#{event.join_code}")
      assert html =~ ">0<"

      # Same reasoning as the question-submission test above: the click
      # itself only returns handle_event's synchronous reply, so the
      # updated count — which arrives via this view's own PubSub
      # broadcast landing back on itself — is only visible on a
      # following render/1 call.
      view |> element("button[phx-value-id='#{question.id}']") |> render_click()
      assert render(view) =~ ">1<"

      view |> element("button[phx-value-id='#{question.id}']") |> render_click()
      assert render(view) =~ ">0<"
    end

    test "ignores a vote on a question id from another event", %{conn: conn} do
      event = event_fixture()
      other_event = event_fixture()
      {conn, _participant} = join_as_participant(conn, event)
      other_question = question_fixture(other_event, participant_fixture(other_event))

      {:ok, view, _html} = live(conn, ~p"/e/#{event.join_code}")

      # No matching button exists on this event's own page — this
      # simulates the client event directly to prove the *server-side*
      # scoping (Events.get_question/2), not just the absent UI element,
      # is what refuses to touch another event's question.
      render_click(view, "toggle_vote", %{"id" => to_string(other_question.id)})

      unchanged = Askroom.Repo.reload!(other_question)
      assert unchanged.vote_count == 0
      assert Askroom.Repo.aggregate(Askroom.Events.Vote, :count) == 0
    end
  end

  describe "live updates reach other sessions" do
    test "a question submitted by one participant appears on another's screen", %{conn: conn} do
      event = event_fixture()
      {conn_a, _a} = join_as_participant(conn, event)
      {conn_b, _b} = join_as_participant(Phoenix.ConnTest.build_conn(), event)

      {:ok, view_a, _html} = live(conn_a, ~p"/e/#{event.join_code}")
      {:ok, view_b, _html} = live(conn_b, ~p"/e/#{event.join_code}")

      view_a |> form("form", question: %{body: "Seen by everyone?"}) |> render_submit()

      assert render(view_b) =~ "Seen by everyone?"
    end

    test "a vote cast by one participant updates another's screen", %{conn: conn} do
      event = event_fixture()
      question = question_fixture(event, participant_fixture(event))
      {conn_a, _a} = join_as_participant(conn, event)
      {conn_b, _b} = join_as_participant(Phoenix.ConnTest.build_conn(), event)

      {:ok, view_a, _html} = live(conn_a, ~p"/e/#{event.join_code}")
      {:ok, view_b, html_b} = live(conn_b, ~p"/e/#{event.join_code}")

      assert html_b =~ ">0<"

      view_a |> element("button[phx-value-id='#{question.id}']") |> render_click()

      assert render(view_b) =~ ">1<"
    end
  end
end
