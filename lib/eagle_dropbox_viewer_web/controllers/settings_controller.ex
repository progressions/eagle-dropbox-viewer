defmodule EagleDropboxViewerWeb.SettingsController do
  use EagleDropboxViewerWeb, :controller

  alias EagleDropboxViewer.Dropbox

  def show(conn, _params) do
    connection = Dropbox.get_connection()

    sample =
      if connection do
        case Dropbox.list_library_entries(10) do
          {:ok, %{"entries" => entries}} -> {:ok, entries}
          {:error, reason} -> {:error, reason}
        end
      else
        :not_connected
      end

    render(conn, :show,
      connection: connection,
      library_path: Dropbox.library_path(),
      sample: sample,
      dropbox_configured?: dropbox_configured?()
    )
  end

  defp dropbox_configured? do
    key = Application.get_env(:eagle_dropbox_viewer, :dropbox_app_key)
    secret = Application.get_env(:eagle_dropbox_viewer, :dropbox_app_secret)
    is_binary(key) and key != "" and is_binary(secret) and secret != ""
  end
end
