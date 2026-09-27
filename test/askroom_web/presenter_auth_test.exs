defmodule AskroomWeb.PresenterAuthTest do
  use AskroomWeb.ConnCase, async: true

  alias Askroom.Accounts
  alias AskroomWeb.PresenterAuth
  alias Phoenix.LiveView
  import Askroom.AccountsFixtures

  @remember_me_cookie "_askroom_web_presenter_remember_me"

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, AskroomWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{presenter: presenter_fixture(), conn: conn}
  end

  describe "log_in_presenter/3" do
    test "stores the presenter token in the session", %{conn: conn, presenter: presenter} do
      conn = PresenterAuth.log_in_presenter(conn, presenter)
      assert token = get_session(conn, :presenter_token)

      assert get_session(conn, :live_socket_id) ==
               "presenters_sessions:#{Base.url_encode64(token)}"

      assert redirected_to(conn) == ~p"/"
      assert Accounts.get_presenter_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{conn: conn, presenter: presenter} do
      conn =
        conn |> put_session(:to_be_removed, "value") |> PresenterAuth.log_in_presenter(presenter)

      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, presenter: presenter} do
      conn =
        conn
        |> put_session(:presenter_return_to, "/hello")
        |> PresenterAuth.log_in_presenter(presenter)

      assert redirected_to(conn) == "/hello"
    end

    test "writes a cookie if remember_me is configured", %{conn: conn, presenter: presenter} do
      conn =
        conn
        |> fetch_cookies()
        |> PresenterAuth.log_in_presenter(presenter, %{"remember_me" => "true"})

      assert get_session(conn, :presenter_token) == conn.cookies[@remember_me_cookie]

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :presenter_token)
      assert max_age == 5_184_000
    end
  end

  describe "logout_presenter/1" do
    test "erases session and cookies", %{conn: conn, presenter: presenter} do
      presenter_token = Accounts.generate_presenter_session_token(presenter)

      conn =
        conn
        |> put_session(:presenter_token, presenter_token)
        |> put_req_cookie(@remember_me_cookie, presenter_token)
        |> fetch_cookies()
        |> PresenterAuth.log_out_presenter()

      refute get_session(conn, :presenter_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
      refute Accounts.get_presenter_by_session_token(presenter_token)
    end

    test "broadcasts to the given live_socket_id", %{conn: conn} do
      live_socket_id = "presenters_sessions:abcdef-token"
      AskroomWeb.Endpoint.subscribe(live_socket_id)

      conn
      |> put_session(:live_socket_id, live_socket_id)
      |> PresenterAuth.log_out_presenter()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}
    end

    test "works even if presenter is already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> PresenterAuth.log_out_presenter()
      refute get_session(conn, :presenter_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "fetch_current_presenter/2" do
    test "authenticates presenter from session", %{conn: conn, presenter: presenter} do
      presenter_token = Accounts.generate_presenter_session_token(presenter)

      conn =
        conn
        |> put_session(:presenter_token, presenter_token)
        |> PresenterAuth.fetch_current_presenter([])

      assert conn.assigns.current_presenter.id == presenter.id
    end

    test "authenticates presenter from cookies", %{conn: conn, presenter: presenter} do
      logged_in_conn =
        conn
        |> fetch_cookies()
        |> PresenterAuth.log_in_presenter(presenter, %{"remember_me" => "true"})

      presenter_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> PresenterAuth.fetch_current_presenter([])

      assert conn.assigns.current_presenter.id == presenter.id
      assert get_session(conn, :presenter_token) == presenter_token

      assert get_session(conn, :live_socket_id) ==
               "presenters_sessions:#{Base.url_encode64(presenter_token)}"
    end

    test "does not authenticate if data is missing", %{conn: conn, presenter: presenter} do
      _ = Accounts.generate_presenter_session_token(presenter)
      conn = PresenterAuth.fetch_current_presenter(conn, [])
      refute get_session(conn, :presenter_token)
      refute conn.assigns.current_presenter
    end
  end

  describe "on_mount :mount_current_presenter" do
    test "assigns current_presenter based on a valid presenter_token", %{
      conn: conn,
      presenter: presenter
    } do
      presenter_token = Accounts.generate_presenter_session_token(presenter)
      session = conn |> put_session(:presenter_token, presenter_token) |> get_session()

      {:cont, updated_socket} =
        PresenterAuth.on_mount(:mount_current_presenter, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_presenter.id == presenter.id
    end

    test "assigns nil to current_presenter assign if there isn't a valid presenter_token", %{
      conn: conn
    } do
      presenter_token = "invalid_token"
      session = conn |> put_session(:presenter_token, presenter_token) |> get_session()

      {:cont, updated_socket} =
        PresenterAuth.on_mount(:mount_current_presenter, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_presenter == nil
    end

    test "assigns nil to current_presenter assign if there isn't a presenter_token", %{conn: conn} do
      session = conn |> get_session()

      {:cont, updated_socket} =
        PresenterAuth.on_mount(:mount_current_presenter, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_presenter == nil
    end
  end

  describe "on_mount :ensure_authenticated" do
    test "authenticates current_presenter based on a valid presenter_token", %{
      conn: conn,
      presenter: presenter
    } do
      presenter_token = Accounts.generate_presenter_session_token(presenter)
      session = conn |> put_session(:presenter_token, presenter_token) |> get_session()

      {:cont, updated_socket} =
        PresenterAuth.on_mount(:ensure_authenticated, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_presenter.id == presenter.id
    end

    test "redirects to login page if there isn't a valid presenter_token", %{conn: conn} do
      presenter_token = "invalid_token"
      session = conn |> put_session(:presenter_token, presenter_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: AskroomWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} =
        PresenterAuth.on_mount(:ensure_authenticated, %{}, session, socket)

      assert updated_socket.assigns.current_presenter == nil
    end

    test "redirects to login page if there isn't a presenter_token", %{conn: conn} do
      session = conn |> get_session()

      socket = %LiveView.Socket{
        endpoint: AskroomWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} =
        PresenterAuth.on_mount(:ensure_authenticated, %{}, session, socket)

      assert updated_socket.assigns.current_presenter == nil
    end
  end

  describe "on_mount :redirect_if_presenter_is_authenticated" do
    test "redirects if there is an authenticated  presenter ", %{conn: conn, presenter: presenter} do
      presenter_token = Accounts.generate_presenter_session_token(presenter)
      session = conn |> put_session(:presenter_token, presenter_token) |> get_session()

      assert {:halt, _updated_socket} =
               PresenterAuth.on_mount(
                 :redirect_if_presenter_is_authenticated,
                 %{},
                 session,
                 %LiveView.Socket{}
               )
    end

    test "doesn't redirect if there is no authenticated presenter", %{conn: conn} do
      session = conn |> get_session()

      assert {:cont, _updated_socket} =
               PresenterAuth.on_mount(
                 :redirect_if_presenter_is_authenticated,
                 %{},
                 session,
                 %LiveView.Socket{}
               )
    end
  end

  describe "redirect_if_presenter_is_authenticated/2" do
    test "redirects if presenter is authenticated", %{conn: conn, presenter: presenter} do
      conn =
        conn
        |> assign(:current_presenter, presenter)
        |> PresenterAuth.redirect_if_presenter_is_authenticated([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/"
    end

    test "does not redirect if presenter is not authenticated", %{conn: conn} do
      conn = PresenterAuth.redirect_if_presenter_is_authenticated(conn, [])
      refute conn.halted
      refute conn.status
    end
  end

  describe "require_authenticated_presenter/2" do
    test "redirects if presenter is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> PresenterAuth.require_authenticated_presenter([])
      assert conn.halted

      assert redirected_to(conn) == ~p"/presenters/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must log in to access this page."
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> PresenterAuth.require_authenticated_presenter([])

      assert halted_conn.halted
      assert get_session(halted_conn, :presenter_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> PresenterAuth.require_authenticated_presenter([])

      assert halted_conn.halted
      assert get_session(halted_conn, :presenter_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> PresenterAuth.require_authenticated_presenter([])

      assert halted_conn.halted
      refute get_session(halted_conn, :presenter_return_to)
    end

    test "does not redirect if presenter is authenticated", %{conn: conn, presenter: presenter} do
      conn =
        conn
        |> assign(:current_presenter, presenter)
        |> PresenterAuth.require_authenticated_presenter([])

      refute conn.halted
      refute conn.status
    end
  end
end
