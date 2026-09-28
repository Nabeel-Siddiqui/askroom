defmodule AskroomWeb.PresenterLive.DashboardTest do
  use AskroomWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Askroom.EventsFixtures

  setup :register_and_log_in_presenter

  test "lists the presenter's own events, not another presenter's", %{
    conn: conn,
    presenter: presenter
  } do
    mine = event_fixture(%{title: "My talk"}, presenter)
    _theirs = event_fixture(%{title: "Not mine"})

    {:ok, _view, html} = live(conn, ~p"/dashboard")

    assert html =~ mine.title
    assert html =~ mine.join_code
    refute html =~ "Not mine"
  end

  test "creates a new event", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    html =
      view
      |> form("form", event: %{title: "Brand new talk"})
      |> render_submit()

    assert html =~ "Brand new talk"
  end

  test "rejects a blank title with an inline error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    html = view |> form("form", event: %{title: ""}) |> render_submit()

    assert html =~ "can&#39;t be blank"
  end

  test "toggles an event between open and closed", %{conn: conn, presenter: presenter} do
    event = event_fixture(%{}, presenter)
    {:ok, view, html} = live(conn, ~p"/dashboard")
    assert html =~ "open"

    html = view |> element("button[phx-value-id='#{event.id}']") |> render_click()
    assert html =~ "closed"
    assert html =~ "Reopen"

    html = view |> element("button[phx-value-id='#{event.id}']") |> render_click()
    assert html =~ "open"
  end
end
