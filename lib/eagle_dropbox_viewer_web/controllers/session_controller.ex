defmodule EagleDropboxViewerWeb.SessionController do
  use EagleDropboxViewerWeb, :controller

  def new(conn, _params) do
    if get_session(conn, :app_authenticated) do
      redirect(conn, to: ~p"/settings")
    else
      render(conn, :new)
    end
  end

  def create(conn, %{"session" => %{"username" => username, "password" => password}}) do
    expected_user = Application.get_env(:eagle_dropbox_viewer, :app_username)
    expected_pass = Application.get_env(:eagle_dropbox_viewer, :app_password)

    valid? =
      is_binary(expected_user) and is_binary(expected_pass) and expected_pass != "" and
        secure_equals?(username, expected_user) and secure_equals?(password, expected_pass)

    if valid? do
      conn
      |> renew_session()
      |> put_session(:app_authenticated, true)
      |> put_flash(:info, "Signed in.")
      |> redirect(to: ~p"/settings")
    else
      conn
      |> put_flash(:error, "Invalid username or password.")
      |> render(:new)
    end
  end

  def delete(conn, _params) do
    conn
    |> renew_session()
    |> put_flash(:info, "Signed out.")
    |> redirect(to: ~p"/login")
  end

  defp secure_equals?(a, b) when is_binary(a) and is_binary(b) do
    byte_size(a) == byte_size(b) and Plug.Crypto.secure_compare(a, b)
  end

  defp secure_equals?(_, _), do: false

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
