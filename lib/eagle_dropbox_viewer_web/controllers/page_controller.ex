defmodule EagleDropboxViewerWeb.PageController do
  use EagleDropboxViewerWeb, :controller

  def home(conn, _params) do
    if get_session(conn, :app_authenticated) do
      redirect(conn, to: ~p"/settings")
    else
      redirect(conn, to: ~p"/login")
    end
  end
end
