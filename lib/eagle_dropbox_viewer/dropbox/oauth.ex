defmodule EagleDropboxViewer.Dropbox.OAuth do
  @moduledoc """
  Dropbox OAuth 2 authorization-code flow with offline refresh tokens.
  """

  @authorize_url "https://www.dropbox.com/oauth2/authorize"
  @token_url "https://api.dropbox.com/oauth2/token"
  @scopes "files.metadata.read files.content.read account_info.read"

  def scopes, do: @scopes

  def authorize_url(state) when is_binary(state) do
    query =
      URI.encode_query(%{
        "client_id" => app_key!(),
        "redirect_uri" => redirect_uri!(),
        "response_type" => "code",
        "token_access_type" => "offline",
        "scope" => @scopes,
        "state" => state
      })

    @authorize_url <> "?" <> query
  end

  def exchange_code(code) when is_binary(code) do
    body = [
      {"code", code},
      {"grant_type", "authorization_code"},
      {"redirect_uri", redirect_uri!()},
      {"client_id", app_key!()},
      {"client_secret", app_secret!()}
    ]

    request_token(body)
  end

  def refresh_access_token(refresh_token) when is_binary(refresh_token) do
    body = [
      {"refresh_token", refresh_token},
      {"grant_type", "refresh_token"},
      {"client_id", app_key!()},
      {"client_secret", app_secret!()}
    ]

    request_token(body)
  end

  defp request_token(body) do
    case Req.post(@token_url, form: body) do
      {:ok, %{status: 200, body: payload}} when is_map(payload) ->
        {:ok, normalize_token_payload(payload)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_token_payload(payload) do
    expires_in = Map.get(payload, "expires_in", 14_400)
    expires_at = DateTime.utc_now() |> DateTime.add(expires_in, :second) |> DateTime.truncate(:second)

    %{
      access_token: payload["access_token"],
      refresh_token: payload["refresh_token"],
      expires_at: expires_at,
      account_id: payload["account_id"],
      uid: payload["uid"],
      scopes: payload["scope"] || @scopes
    }
  end

  defp app_key!, do: fetch_env!(:dropbox_app_key)
  defp app_secret!, do: fetch_env!(:dropbox_app_secret)
  defp redirect_uri!, do: fetch_env!(:dropbox_redirect_uri)

  defp fetch_env!(key) do
    case Application.get_env(:eagle_dropbox_viewer, key) do
      value when is_binary(value) and value != "" -> value
      _ -> raise "Missing config :eagle_dropbox_viewer, #{inspect(key)} (set env var)"
    end
  end
end
