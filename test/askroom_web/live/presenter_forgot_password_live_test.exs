defmodule AskroomWeb.PresenterForgotPasswordLiveTest do
  use AskroomWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Askroom.AccountsFixtures

  alias Askroom.Accounts
  alias Askroom.Repo

  describe "Forgot password page" do
    test "renders email page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/presenters/reset_password")

      assert html =~ "Forgot your password?"
      assert has_element?(lv, ~s|a[href="#{~p"/presenters/register"}"]|, "Register")
      assert has_element?(lv, ~s|a[href="#{~p"/presenters/log_in"}"]|, "Log in")
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_presenter(presenter_fixture())
        |> live(~p"/presenters/reset_password")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end
  end

  describe "Reset link" do
    setup do
      %{presenter: presenter_fixture()}
    end

    test "sends a new reset password token", %{conn: conn, presenter: presenter} do
      {:ok, lv, _html} = live(conn, ~p"/presenters/reset_password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", presenter: %{"email" => presenter.email})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"

      assert Repo.get_by!(Accounts.PresenterToken, presenter_id: presenter.id).context ==
               "reset_password"
    end

    test "does not send reset password token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/presenters/reset_password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", presenter: %{"email" => "unknown@example.com"})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      assert Repo.all(Accounts.PresenterToken) == []
    end
  end
end
