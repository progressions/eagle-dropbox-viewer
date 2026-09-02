defmodule EagleDropboxViewerWeb.PageController do
  use EagleDropboxViewerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
