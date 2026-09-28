defmodule AskroomWeb.PresenterLive.ProjectorTest do
  use AskroomWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Askroom.EventsFixtures

  alias Askroom.Events

  setup :register_and_log_in_presenter

  test "redirects to the dashboard for an event the presenter doesn't own", %{conn: conn} do
    event = event_fixture()

    assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
             live(conn, ~p"/dashboard/events/#{event.id}/projector")
  end

  test "shows top questions by vote when no poll is live", %{conn: conn, presenter: presenter} do
    event = event_fixture(%{}, presenter)
    low = question_fixture(event, participant_fixture(event), %{body: "Low votes"})
    high = question_fixture(event, participant_fixture(event), %{body: "High votes"})

    for _ <- 1..3, do: Events.toggle_vote(participant_fixture(event), high)
    Events.toggle_vote(participant_fixture(event), low)

    {:ok, _view, html} = live(conn, ~p"/dashboard/events/#{event.id}/projector")

    assert html =~ "High votes"
    assert html =~ "Low votes"
    assert html =~ event.title
  end

  test "switches to a live poll's results when one is launched", %{
    conn: conn,
    presenter: presenter
  } do
    event = event_fixture(%{}, presenter)
    _question = question_fixture(event, participant_fixture(event))
    poll = poll_fixture(presenter, event, %{options: ["A", "B"]})

    {:ok, view, html} = live(conn, ~p"/dashboard/events/#{event.id}/projector")
    refute html =~ poll.question_text

    {:ok, poll} = Events.launch_poll(presenter, event, poll)
    assert render(view) =~ poll.question_text

    {:ok, _} = Events.answer_poll(event, participant_fixture(event), poll, "A")
    assert render(view) =~ ~r/A.*>1</s
  end

  test "switches back to top questions once the live poll is closed", %{
    conn: conn,
    presenter: presenter
  } do
    event = event_fixture(%{}, presenter)
    # A body without an apostrophe — HeEx HTML-escapes it to `&#39;`
    # on render, so comparing against the raw fixture string (which
    # defaults to "What's the roadmap for this?") would never match.
    question = question_fixture(event, participant_fixture(event), %{body: "Roadmap question"})
    poll = poll_fixture(presenter, event)
    {:ok, poll} = Events.launch_poll(presenter, event, poll)

    {:ok, view, html} = live(conn, ~p"/dashboard/events/#{event.id}/projector")
    assert html =~ poll.question_text

    {:ok, _} = Events.close_poll(presenter, event, poll)

    html = render(view)
    refute html =~ poll.question_text
    assert html =~ question.body
  end
end
