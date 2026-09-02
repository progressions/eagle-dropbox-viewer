defmodule EagleDropboxViewerWeb.AppAuth do
  @moduledoc false
  import Phoenix.LiveView

  def on_mount(:ensure_authenticated, _params, session, socket) do
    if session["app_authenticated"] do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end
end
