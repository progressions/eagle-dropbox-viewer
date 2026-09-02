defmodule EagleDropboxViewerWeb.PageControllerTest do
  use EagleDropboxViewerWeb.ConnCase

  test "GET / redirects to login when signed out", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/login"
  end

  test "GET /settings redirects to login when signed out", %{conn: conn} do
    conn = get(conn, ~p"/settings")
    assert redirected_to(conn) == "/login"
  end

  test "login then settings", %{conn: conn} do
    conn =
      post(conn, ~p"/login", %{
        "session" => %{"username" => "test", "password" => "test"}
      })

    assert redirected_to(conn) == ~p"/settings"

    conn = get(recycle(conn), ~p"/settings")
    body = html_response(conn, 200)
    assert body =~ "Dropbox"
  end
end
