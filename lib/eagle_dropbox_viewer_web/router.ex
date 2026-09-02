defmodule EagleDropboxViewerWeb.Router do
  use EagleDropboxViewerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EagleDropboxViewerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :require_app_auth do
    plug EagleDropboxViewerWeb.Plugs.RequireAppAuth
  end

  scope "/", EagleDropboxViewerWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  scope "/", EagleDropboxViewerWeb do
    pipe_through [:browser, :require_app_auth]

    get "/settings", SettingsController, :show
    post "/settings/sync", SettingsController, :sync
    get "/auth/dropbox", DropboxAuthController, :start
    get "/auth/dropbox/callback", DropboxAuthController, :callback
    post "/auth/dropbox/disconnect", DropboxAuthController, :disconnect

    get "/media/thumb/:id", MediaController, :thumb
    get "/media/original/:id", MediaController, :original
  end

  live_session :authenticated,
    on_mount: [{EagleDropboxViewerWeb.AppAuth, :ensure_authenticated}],
    layout: {EagleDropboxViewerWeb.Layouts, :root} do
    scope "/", EagleDropboxViewerWeb do
      pipe_through [:browser, :require_app_auth]

      live "/browse", BrowseLive, :index
      live "/browse/:id", BrowseLive, :show
    end
  end

  if Application.compile_env(:eagle_dropbox_viewer, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EagleDropboxViewerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
