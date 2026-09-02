defmodule EagleDropboxViewerWeb.DropboxAuthController do
  use EagleDropboxViewerWeb, :controller

  alias EagleDropboxViewer.Dropbox
  alias EagleDropboxViewer.Dropbox.OAuth

  def start(conn, _params) do
    state = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    conn
    |> put_session(:dropbox_oauth_state, state)
    |> redirect(external: OAuth.authorize_url(state))
  rescue
    e in RuntimeError ->
      conn
      |> put_flash(:error, Exception.message(e))
      |> redirect(to: ~p"/settings")
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    expected = get_session(conn, :dropbox_oauth_state)

    cond do
      not is_binary(expected) or expected == "" ->
        fail(conn, "Missing OAuth state. Try Connect again.")

      not Plug.Crypto.secure_compare(state || "", expected) ->
        fail(conn, "OAuth state mismatch. Try Connect again.")

      true ->
        conn = delete_session(conn, :dropbox_oauth_state)

        case OAuth.exchange_code(code) do
          {:ok, payload} ->
            case Dropbox.upsert_from_oauth(payload) do
              {:ok, _connection} ->
                conn
                |> put_flash(:info, "Dropbox connected.")
                |> redirect(to: ~p"/settings")

              {:error, reason} ->
                fail(conn, "Could not save Dropbox connection: #{inspect(reason)}")
            end

          {:error, reason} ->
            fail(conn, "Token exchange failed: #{inspect(reason)}")
        end
    end
  end

  def callback(conn, %{"error" => error} = params) do
    desc = params["error_description"] || error
    fail(conn, "Dropbox denied access: #{desc}")
  end

  def callback(conn, _params) do
    fail(conn, "Dropbox callback missing code.")
  end

  def disconnect(conn, _params) do
    _ = Dropbox.delete_connection()

    conn
    |> put_flash(:info, "Dropbox disconnected.")
    |> redirect(to: ~p"/settings")
  end

  defp fail(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/settings")
  end
end
