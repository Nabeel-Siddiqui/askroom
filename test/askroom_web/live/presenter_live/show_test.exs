defmodule AskroomWeb.PresenterLive.ShowTest do
  use AskroomWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Askroom.EventsFixtures

  alias Askroom.Events

  setup :register_and_log_in_presenter

  describe "mount" do
    test "renders the event, join link, and a QR code", %{conn: conn, presenter: presenter} do
      event = event_fixture(%{title: "My talk"}, presenter)

      {:ok, _view, html} = live(conn, ~p"/dashboard/events/#{event.id}")

      assert html =~ "My talk"
      assert html =~ event.join_code
      assert html =~ "<svg"
    end

    test "redirects to the dashboard for an event that doesn't exist", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
               live(conn, ~p"/dashboard/events/999999")
    end

    test "redirects to the dashboard for another presenter's event", %{conn: conn} do
      event = event_fixture()

      assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
               live(conn, ~p"/dashboard/events/#{event.id}")
    end
  end

  describe "opening and closing the event" do
    test "toggles status", %{conn: conn, presenter: presenter} do
      event = event_fixture(%{}, presenter)
      {:ok, view, html} = live(conn, ~p"/dashboard/events/#{event.id}")
      assert html =~ "Close event"

      view |> element("button", "Close event") |> render_click()
      assert render(view) =~ "Reopen event"
    end
  end

  describe "moderation" do
    test "approving a pending question moves it out of the pending state", %{
      conn: conn,
      presenter: presenter
    } do
      event = event_fixture(%{moderation_enabled: true}, presenter)

      {:ok, question} =
        Events.create_question(event, participant_fixture(event), %{body: "Pending?"})

      {:ok, view, html} = live(conn, ~p"/dashboard/events/#{event.id}")
      assert html =~ "Approve"

      view |> element("button[phx-value-id='#{question.id}']", "Approve") |> render_click()

      # Same reasoning as AudienceLive's tests: moderation actions here
      # broadcast and let the self-received message update this page's
      # assigns, so render_click/1's own return doesn't see it yet — a
      # following render/1 does.
      refute render(view) =~ "Approve"
      assert {:ok, %{status: :visible}} = Events.get_question(event, question.id)
    end

    test "marking a question answered and hiding it both work", %{
      conn: conn,
      presenter: presenter
    } do
      event = event_fixture(%{}, presenter)
      question = question_fixture(event, participant_fixture(event))

      {:ok, view, _html} = live(conn, ~p"/dashboard/events/#{event.id}")

      view |> element("button[phx-value-id='#{question.id}']", "Mark answered") |> render_click()
      assert {:ok, %{status: :answered}} = Events.get_question(event, question.id)
      # Let the "answered" broadcast's self-echo land before the next
      # click, rather than relying on incidental timing.
      render(view)

      view |> element("button[phx-value-id='#{question.id}']", "Hide") |> render_click()
      refute render(view) =~ question.body
      assert {:ok, %{status: :hidden}} = Events.get_question(event, question.id)
    end
  end

  describe "polls" do
    test "creates a poll from newline-separated options", %{conn: conn, presenter: presenter} do
      event = event_fixture(%{}, presenter)
      {:ok, view, _html} = live(conn, ~p"/dashboard/events/#{event.id}")

      html =
        view
        |> form("form", poll: %{question_text: "Favorite?", options: "Tabs\nSpaces"})
        |> render_submit()

      assert html =~ "Favorite?"
      assert html =~ "Launch"
      assert [poll] = Events.list_polls(event)
      assert poll.options == ["Tabs", "Spaces"]
    end

    test "launching a poll shows its live results, updated as answers come in", %{
      conn: conn,
      presenter: presenter
    } do
      event = event_fixture(%{}, presenter)
      poll = poll_fixture(presenter, event, %{options: ["Rust", "Elixir"]})

      {:ok, view, _html} = live(conn, ~p"/dashboard/events/#{event.id}")

      view |> element("button[phx-value-id='#{poll.id}']", "Launch") |> render_click()
      assert render(view) =~ "Close"

      {:ok, poll} = Events.get_poll(event, poll.id)
      {:ok, _} = Events.answer_poll(event, participant_fixture(event), poll, "Elixir")

      assert render(view) =~ ~r/Elixir.*>1</s
    end

    test "closing a poll freezes its results instead of clearing them", %{
      conn: conn,
      presenter: presenter
    } do
      event = event_fixture(%{}, presenter)
      poll = poll_fixture(presenter, event)
      {:ok, poll} = Events.launch_poll(presenter, event, poll)
      {:ok, _} = Events.answer_poll(event, participant_fixture(event), poll, "Search")

      {:ok, view, _html} = live(conn, ~p"/dashboard/events/#{event.id}")

      view |> element("button[phx-value-id='#{poll.id}']", "Close") |> render_click()
      html = render(view)
      assert html =~ "Closed"
      assert html =~ ">1<"
    end
  end

  describe "presence" do
    test "shows a live count of joined participants", %{conn: conn, presenter: presenter} do
      event = event_fixture(%{}, presenter)

      {:ok, _presenter_view, html} = live(conn, ~p"/dashboard/events/#{event.id}")
      assert html =~ "0 people here now"

      {audience_conn, _participant} = join_as_participant(build_conn(), event)
      {:ok, _audience_view, _html} = live(audience_conn, ~p"/e/#{event.join_code}")

      {:ok, _presenter_view2, html2} = live(conn, ~p"/dashboard/events/#{event.id}")
      assert html2 =~ "1 person here now"
    end
  end
end
