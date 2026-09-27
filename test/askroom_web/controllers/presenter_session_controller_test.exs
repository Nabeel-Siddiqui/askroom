defmodule AskroomWeb.PresenterSessionControllerTest do
  use AskroomWeb.ConnCase, async: true

  import Askroom.AccountsFixtures

  setup do
    %{presenter: presenter_fixture()}
  end

  describe "POST /presenters/log_in" do
    test "logs the presenter in", %{conn: conn, presenter: presenter} do
      conn =
        post(conn, ~p"/presenters/log_in", %{
          "presenter" => %{"email" => presenter.email, "password" => valid_presenter_password()}
        })

      assert get_session(conn, :presenter_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ presenter.email
      assert response =~ ~p"/presenters/settings"
      assert response =~ ~p"/presenters/log_out"
    end

    test "logs the presenter in with remember me", %{conn: conn, presenter: presenter} do
      conn =
        post(conn, ~p"/presenters/log_in", %{
          "presenter" => %{
            "email" => presenter.email,
            "password" => valid_presenter_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_askroom_web_presenter_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the presenter in with return to", %{conn: conn, presenter: presenter} do
      conn =
        conn
        |> init_test_session(presenter_return_to: "/foo/bar")
        |> post(~p"/presenters/log_in", %{
          "presenter" => %{
            "email" => presenter.email,
            "password" => valid_presenter_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "login following registration", %{conn: conn, presenter: presenter} do
      conn =
        conn
        |> post(~p"/presenters/log_in", %{
          "_action" => "registered",
          "presenter" => %{
            "email" => presenter.email,
            "password" => valid_presenter_password()
          }
        })

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Account created successfully"
    end

    test "login following password update", %{conn: conn, presenter: presenter} do
      conn =
        conn
        |> post(~p"/presenters/log_in", %{
          "_action" => "password_updated",
          "presenter" => %{
            "email" => presenter.email,
            "password" => valid_presenter_password()
          }
        })

      assert redirected_to(conn) == ~p"/presenters/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password updated successfully"
    end

    test "redirects to login page with invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/presenters/log_in", %{
          "presenter" => %{"email" => "invalid@email.com", "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/presenters/log_in"
    end
  end

  describe "DELETE /presenters/log_out" do
    test "logs the presenter out", %{conn: conn, presenter: presenter} do
      conn = conn |> log_in_presenter(presenter) |> delete(~p"/presenters/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :presenter_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the presenter is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/presenters/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :presenter_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
