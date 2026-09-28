defmodule AskroomWeb.PresenterLoginLiveTest do
  use AskroomWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Askroom.AccountsFixtures

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/presenters/log_in")

      assert html =~ "Log in"
      assert html =~ "Register"
      assert html =~ "Forgot your password?"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_presenter(presenter_fixture())
        |> live(~p"/presenters/log_in")
        |> follow_redirect(conn, "/dashboard")

      assert {:ok, _conn} = result
    end
  end

  describe "presenter login" do
    test "redirects if presenter login with valid credentials", %{conn: conn} do
      password = "123456789abcd"
      presenter = presenter_fixture(%{password: password})

      {:ok, lv, _html} = live(conn, ~p"/presenters/log_in")

      form =
        form(lv, "#login_form",
          presenter: %{email: presenter.email, password: password, remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "redirects to login page with a flash error if there are no valid credentials", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/presenters/log_in")

      form =
        form(lv, "#login_form",
          presenter: %{email: "test@email.com", password: "123456", remember_me: true}
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"

      assert redirected_to(conn) == "/presenters/log_in"
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/presenters/log_in")

      {:ok, _login_live, login_html} =
        lv
        |> element(~s|main a:fl-contains("Sign up")|)
        |> render_click()
        |> follow_redirect(conn, ~p"/presenters/register")

      assert login_html =~ "Register"
    end

    test "redirects to forgot password page when the Forgot Password button is clicked", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/presenters/log_in")

      {:ok, conn} =
        lv
        |> element(~s|main a:fl-contains("Forgot your password?")|)
        |> render_click()
        |> follow_redirect(conn, ~p"/presenters/reset_password")

      assert conn.resp_body =~ "Forgot your password?"
    end
  end
end
