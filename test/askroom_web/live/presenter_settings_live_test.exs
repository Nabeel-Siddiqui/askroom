defmodule AskroomWeb.PresenterSettingsLiveTest do
  use AskroomWeb.ConnCase, async: true

  alias Askroom.Accounts
  import Phoenix.LiveViewTest
  import Askroom.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_presenter(presenter_fixture())
        |> live(~p"/presenters/settings")

      assert html =~ "Change Email"
      assert html =~ "Change Password"
    end

    test "redirects if presenter is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/presenters/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/presenters/log_in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      password = valid_presenter_password()
      presenter = presenter_fixture(%{password: password})
      %{conn: log_in_presenter(conn, presenter), presenter: presenter, password: password}
    end

    test "updates the presenter email", %{conn: conn, password: password, presenter: presenter} do
      new_email = unique_presenter_email()

      {:ok, lv, _html} = live(conn, ~p"/presenters/settings")

      result =
        lv
        |> form("#email_form", %{
          "current_password" => password,
          "presenter" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_presenter_by_email(presenter.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/presenters/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "current_password" => "invalid",
          "presenter" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, presenter: presenter} do
      {:ok, lv, _html} = live(conn, ~p"/presenters/settings")

      result =
        lv
        |> form("#email_form", %{
          "current_password" => "invalid",
          "presenter" => %{"email" => presenter.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
      assert result =~ "is not valid"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      password = valid_presenter_password()
      presenter = presenter_fixture(%{password: password})
      %{conn: log_in_presenter(conn, presenter), presenter: presenter, password: password}
    end

    test "updates the presenter password", %{conn: conn, presenter: presenter, password: password} do
      new_password = valid_presenter_password()

      {:ok, lv, _html} = live(conn, ~p"/presenters/settings")

      form =
        form(lv, "#password_form", %{
          "current_password" => password,
          "presenter" => %{
            "email" => presenter.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/presenters/settings"

      assert get_session(new_password_conn, :presenter_token) !=
               get_session(conn, :presenter_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_presenter_by_email_and_password(presenter.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/presenters/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "current_password" => "invalid",
          "presenter" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Change Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/presenters/settings")

      result =
        lv
        |> form("#password_form", %{
          "current_password" => "invalid",
          "presenter" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Change Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
      assert result =~ "is not valid"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      presenter = presenter_fixture()
      email = unique_presenter_email()

      token =
        extract_presenter_token(fn url ->
          Accounts.deliver_presenter_update_email_instructions(
            %{presenter | email: email},
            presenter.email,
            url
          )
        end)

      %{conn: log_in_presenter(conn, presenter), token: token, email: email, presenter: presenter}
    end

    test "updates the presenter email once", %{
      conn: conn,
      presenter: presenter,
      token: token,
      email: email
    } do
      {:error, redirect} = live(conn, ~p"/presenters/settings/confirm_email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/presenters/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Accounts.get_presenter_by_email(presenter.email)
      assert Accounts.get_presenter_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/presenters/settings/confirm_email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/presenters/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, presenter: presenter} do
      {:error, redirect} = live(conn, ~p"/presenters/settings/confirm_email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/presenters/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Accounts.get_presenter_by_email(presenter.email)
    end

    test "redirects if presenter is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/presenters/settings/confirm_email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/presenters/log_in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end
end
