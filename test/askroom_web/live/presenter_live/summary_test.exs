defmodule AskroomWeb.PresenterLive.SummaryTest do
  use AskroomWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Askroom.EventsFixtures

  alias Askroom.Events

  setup :register_and_log_in_presenter

  test "redirects to the dashboard for an event the presenter doesn't own", %{conn: conn} do
    event = event_fixture()

    assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
             live(conn, ~p"/dashboard/events/#{event.id}/summary")
  end

  test "lists questions by vote count and each poll's final results", %{
    conn: conn,
    presenter: presenter
  } do
    event = event_fixture(%{}, presenter)

    low = question_fixture(event, participant_fixture(event), %{body: "Low votes"})
    high = question_fixture(event, participant_fixture(event), %{body: "High votes"})
    Events.toggle_vote(participant_fixture(event), high)
    Events.toggle_vote(participant_fixture(event), high)

    poll = poll_fixture(presenter, event, %{options: ["Yes", "No"]})
    {:ok, poll} = Events.launch_poll(presenter, event, poll)
    {:ok, _} = Events.answer_poll(event, participant_fixture(event), poll, "Yes")
    {:ok, poll} = Events.close_poll(presenter, event, poll)

    draft_poll = poll_fixture(presenter, event, %{question_text: "Never launched"})

    {:ok, _view, html} = live(conn, ~p"/dashboard/events/#{event.id}/summary")

    assert html =~ event.title
    assert html =~ high.body
    assert html =~ low.body
    assert html =~ poll.question_text
    assert html =~ "Yes"
    assert html =~ ">1<"
    refute html =~ draft_poll.question_text

    high_index = :binary.match(html, high.body) |> elem(0)
    low_index = :binary.match(html, low.body) |> elem(0)
    assert high_index < low_index
  end

  test "shows placeholders when there were no questions or polls", %{
    conn: conn,
    presenter: presenter
  } do
    event = event_fixture(%{}, presenter)

    {:ok, _view, html} = live(conn, ~p"/dashboard/events/#{event.id}/summary")

    assert html =~ "No questions were asked"
    assert html =~ "No polls were run"
  end
end
