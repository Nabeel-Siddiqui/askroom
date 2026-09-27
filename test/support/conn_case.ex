defmodule AskroomWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AskroomWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint AskroomWeb.Endpoint

      use AskroomWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import AskroomWeb.ConnCase
    end
  end

  setup tags do
    Askroom.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in presenters.

      setup :register_and_log_in_presenter

  It stores an updated connection and a registered presenter in the
  test context.
  """
  def register_and_log_in_presenter(%{conn: conn}) do
    presenter = Askroom.AccountsFixtures.presenter_fixture()
    %{conn: log_in_presenter(conn, presenter), presenter: presenter}
  end

  @doc """
  Logs the given `presenter` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_presenter(conn, presenter) do
    token = Askroom.Accounts.generate_presenter_session_token(presenter)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:presenter_token, token)
  end

  @doc """
  Joins `event` as a fresh anonymous participant, mirroring what
  `AskroomWeb.JoinController` does for a real visitor, without going
  through the controller/HTTP round trip. Returns `{conn, participant}`.
  """
  def join_as_participant(conn, event) do
    {:ok, participant} = Askroom.Events.create_participant(event)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(AskroomWeb.ParticipantAuth.session_key(event), participant.id)

    {conn, participant}
  end
end
