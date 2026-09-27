defmodule AskroomWeb.PresenterConfirmationInstructionsLiveTest do
  use AskroomWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Askroom.AccountsFixtures

  alias Askroom.Accounts
  alias Askroom.Repo

  setup do
    %{presenter: presenter_fixture()}
  end

  describe "Resend confirmation" do
    test "renders the resend confirmation page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/presenters/confirm")
      assert html =~ "Resend confirmation instructions"
    end

    test "sends a new confirmation token", %{conn: conn, presenter: presenter} do
      {:ok, lv, _html} = live(conn, ~p"/presenters/confirm")

      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", presenter: %{email: presenter.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      assert Repo.get_by!(Accounts.PresenterToken, presenter_id: presenter.id).context ==
               "confirm"
    end

    test "does not send confirmation token if presenter is confirmed", %{
      conn: conn,
      presenter: presenter
    } do
      Repo.update!(Accounts.Presenter.confirm_changeset(presenter))

      {:ok, lv, _html} = live(conn, ~p"/presenters/confirm")

      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", presenter: %{email: presenter.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      refute Repo.get_by(Accounts.PresenterToken, presenter_id: presenter.id)
    end

    test "does not send confirmation token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/presenters/confirm")

      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", presenter: %{email: "unknown@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      assert Repo.all(Accounts.PresenterToken) == []
    end
  end
end
