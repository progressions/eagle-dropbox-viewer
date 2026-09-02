defmodule EagleDropboxViewer.Dropbox.Client do
  @moduledoc """
  Thin Dropbox HTTP client. Callers pass a decrypted access token.
  """

  @api "https://api.dropboxapi.com/2"

  def get_current_account(access_token) do
    post_json("/users/get_current_account", access_token, nil)
  end

  def list_folder(access_token, path, opts \\ []) do
    body = %{
      "path" => path,
      "recursive" => Keyword.get(opts, :recursive, false),
      "limit" => Keyword.get(opts, :limit, 25)
    }

    post_json("/files/list_folder", access_token, body)
  end

  defp post_json(path, access_token, body) do
    opts = [
      headers: [
        {"authorization", "Bearer " <> access_token},
        {"content-type", "application/json"}
      ]
    ]

    opts =
      if is_nil(body) do
        Keyword.put(opts, :body, "null")
      else
        Keyword.put(opts, :json, body)
      end

    case Req.post(@api <> path, opts) do
      {:ok, %{status: 200, body: payload}} ->
        {:ok, payload}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
