defmodule EagleDropboxViewerWeb.MediaController do
  use EagleDropboxViewerWeb, :controller

  alias EagleDropboxViewer.Dropbox
  alias EagleDropboxViewer.Dropbox.Client
  alias EagleDropboxViewer.Library

  def thumb(conn, %{"id" => id}) do
    redirect_temp_link(conn, id, :thumb)
  end

  def original(conn, %{"id" => id}) do
    redirect_temp_link(conn, id, :original)
  end

  defp redirect_temp_link(conn, id, kind) do
    case Library.get_item(id) do
      nil ->
        send_resp(conn, 404, "Not found")

      item ->
        Dropbox.with_access_token(fn token ->
          paths =
            case kind do
              :original -> [Library.original_path(item)]
              :thumb ->
                if item.has_thumb do
                  Library.thumb_path(item) ++ [Library.original_path(item)]
                else
                  [Library.original_path(item)]
                end
            end

          case first_temp_link(token, paths) do
            {:ok, link} ->
              redirect(conn, external: link)

            {:error, _} ->
              send_resp(conn, 404, "Media unavailable")
          end
        end)
        |> case do
          %Plug.Conn{} = conn -> conn
          {:error, :not_connected} -> send_resp(conn, 503, "Dropbox not connected")
          {:error, _} -> send_resp(conn, 502, "Dropbox error")
        end
    end
  end

  defp first_temp_link(_token, []), do: {:error, :exhausted}

  defp first_temp_link(token, [path | rest]) do
    case Client.get_temporary_link(token, path) do
      {:ok, link} -> {:ok, link}
      {:error, _} -> first_temp_link(token, rest)
    end
  end
end
