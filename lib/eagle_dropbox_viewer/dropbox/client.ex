defmodule EagleDropboxViewer.Dropbox.Client do
  @moduledoc """
  Thin Dropbox HTTP client. Callers pass a decrypted access token.
  """

  @api "https://api.dropboxapi.com/2"
  @content "https://content.dropboxapi.com/2"

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

  def download(access_token, path) when is_binary(path) do
    arg = Jason.encode!(%{"path" => path})

    case Req.post(@content <> "/files/download",
           headers: [
             {"authorization", "Bearer " <> access_token},
             {"dropbox-api-arg", arg}
           ],
           decode_body: false
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:download_http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_temporary_link(access_token, path) when is_binary(path) do
    case post_json("/files/get_temporary_link", access_token, %{"path" => path}) do
      {:ok, %{"link" => link}} -> {:ok, link}
      {:ok, other} -> {:error, {:unexpected_temp_link, other}}
      {:error, reason} -> {:error, reason}
    end
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
