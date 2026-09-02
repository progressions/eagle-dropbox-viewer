defmodule EagleDropboxViewerWeb.SettingsController do
  use EagleDropboxViewerWeb, :controller

  alias EagleDropboxViewer.Dropbox
  alias EagleDropboxViewer.Library

  def show(conn, _params) do
    connection = Dropbox.get_connection()
    sync = Library.latest_sync()

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
      dropbox_configured?: dropbox_configured?(),
      sync: sync,
      item_count: Library.item_count()
    )
  end

  def sync(conn, _params) do
    case Library.sync_from_dropbox() do
      {:ok, sync} ->
        conn
        |> put_flash(:info, "Synced #{sync.item_count} items.")
        |> redirect(to: ~p"/settings")

      {:error, :not_connected} ->
        conn
        |> put_flash(:error, "Connect Dropbox first.")
        |> redirect(to: ~p"/settings")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Sync failed: #{inspect(reason)}")
        |> redirect(to: ~p"/settings")
    end
  end

  defp dropbox_configured? do
    key = Application.get_env(:eagle_dropbox_viewer, :dropbox_app_key)
    secret = Application.get_env(:eagle_dropbox_viewer, :dropbox_app_secret)
    is_binary(key) and key != "" and is_binary(secret) and secret != ""
  end
end
