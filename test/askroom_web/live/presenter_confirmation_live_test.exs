defmodule AskroomWeb.PresenterConfirmationLiveTest do
  use AskroomWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Askroom.AccountsFixtures

  alias Askroom.Accounts
  alias Askroom.Repo

  setup do
    %{presenter: presenter_fixture()}
  end

  describe "Confirm presenter" do
    test "renders confirmation page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/presenters/confirm/some-token")
      assert html =~ "Confirm Account"
    end

    test "confirms the given token once", %{conn: conn, presenter: presenter} do
      token =
        extract_presenter_token(fn url ->
          Accounts.deliver_presenter_confirmation_instructions(presenter, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/presenters/confirm/#{token}")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert {:ok, conn} = result

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Presenter confirmed successfully"

      assert Accounts.get_presenter!(presenter.id).confirmed_at
      refute get_session(conn, :presenter_token)
      assert Repo.all(Accounts.PresenterToken) == []

      # when not logged in
      {:ok, lv, _html} = live(conn, ~p"/presenters/confirm/#{token}")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert {:ok, conn} = result

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Presenter confirmation link is invalid or it has expired"

      # when logged in
      conn =
        build_conn()
        |> log_in_presenter(presenter)

      {:ok, lv, _html} = live(conn, ~p"/presenters/confirm/#{token}")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert {:ok, conn} = result
      refute Phoenix.Flash.get(conn.assigns.flash, :error)
    end

    test "does not confirm email with invalid token", %{conn: conn, presenter: presenter} do
      {:ok, lv, _html} = live(conn, ~p"/presenters/confirm/invalid-token")

      {:ok, conn} =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Presenter confirmation link is invalid or it has expired"

      refute Accounts.get_presenter!(presenter.id).confirmed_at
    end
  end
end
