defmodule AskroomWeb.PresenterSessionController do
  use AskroomWeb, :controller

  alias Askroom.Accounts
  alias AskroomWeb.PresenterAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:presenter_return_to, ~p"/presenters/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"presenter" => presenter_params}, info) do
    %{"email" => email, "password" => password} = presenter_params

    if presenter = Accounts.get_presenter_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> PresenterAuth.log_in_presenter(presenter, presenter_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/presenters/log_in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> PresenterAuth.log_out_presenter()
  end
end
