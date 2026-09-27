defmodule AskroomWeb.Router do
  use AskroomWeb, :router

  import AskroomWeb.PresenterAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AskroomWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_presenter
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AskroomWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/join", JoinController, :new
    post "/join", JoinController, :create
    get "/join/:code", JoinController, :join

    live_session :participant,
      on_mount: [{AskroomWeb.ParticipantAuth, :require_participant}] do
      live "/e/:code", AudienceLive, :show
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", AskroomWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:askroom, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AskroomWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", AskroomWeb do
    pipe_through [:browser, :redirect_if_presenter_is_authenticated]

    live_session :redirect_if_presenter_is_authenticated,
      on_mount: [{AskroomWeb.PresenterAuth, :redirect_if_presenter_is_authenticated}] do
      live "/presenters/register", PresenterRegistrationLive, :new
      live "/presenters/log_in", PresenterLoginLive, :new
      live "/presenters/reset_password", PresenterForgotPasswordLive, :new
      live "/presenters/reset_password/:token", PresenterResetPasswordLive, :edit
    end

    post "/presenters/log_in", PresenterSessionController, :create
  end

  scope "/", AskroomWeb do
    pipe_through [:browser, :require_authenticated_presenter]

    live_session :require_authenticated_presenter,
      on_mount: [{AskroomWeb.PresenterAuth, :ensure_authenticated}] do
      live "/presenters/settings", PresenterSettingsLive, :edit
      live "/presenters/settings/confirm_email/:token", PresenterSettingsLive, :confirm_email
    end
  end

  scope "/", AskroomWeb do
    pipe_through [:browser]

    delete "/presenters/log_out", PresenterSessionController, :delete

    live_session :current_presenter,
      on_mount: [{AskroomWeb.PresenterAuth, :mount_current_presenter}] do
      live "/presenters/confirm/:token", PresenterConfirmationLive, :edit
      live "/presenters/confirm", PresenterConfirmationInstructionsLive, :new
    end
  end
end
