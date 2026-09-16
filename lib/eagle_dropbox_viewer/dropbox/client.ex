defmodule EagleDropboxViewer.Dropbox.Client do
  @moduledoc """
  Thin Dropbox HTTP client. Callers pass a decrypted access token.
  """

  require Logger

  @api "https://api.dropboxapi.com/2"
  @content "https://content.dropboxapi.com/2"
  @recv_timeout 120_000

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

  def list_folder_continue(access_token, cursor) when is_binary(cursor) do
    post_json("/files/list_folder/continue", access_token, %{"cursor" => cursor})
  end

  @doc """
  Cursor for future deltas without listing existing entries.
  """
  def get_latest_cursor(access_token, path, opts \\ []) do
    body = %{
      "path" => path,
      "recursive" => Keyword.get(opts, :recursive, false)
    }

    case post_json("/files/list_folder/get_latest_cursor", access_token, body) do
      {:ok, %{"cursor" => cursor}} when is_binary(cursor) -> {:ok, cursor}
      {:ok, other} -> {:error, {:unexpected_cursor, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stream list_folder pages into an accumulator. Never builds a full entry list.

  Returns `{:ok, {acc, cursor}}` where `cursor` is the final page cursor (for
  persisting deltas). `fun` is `(entry, acc) -> acc`.
  """
  def list_folder_reduce(access_token, path, opts, acc, fun)
      when is_list(opts) and is_function(fun, 2) do
    limit = Keyword.get(opts, :limit, 2000)
    recursive = Keyword.get(opts, :recursive, false)

    with {:ok, page} <- list_folder(access_token, path, limit: limit, recursive: recursive) do
      reduce_pages(access_token, page, acc, fun, 1)
    end
  end

  @doc """
  Continue from a saved cursor. Returns `{:ok, {acc, cursor}}` or `{:error, :cursor_reset}`.
  """
  def list_folder_continue_reduce(access_token, cursor, acc, fun)
      when is_binary(cursor) and is_function(fun, 2) do
    case list_folder_continue(access_token, cursor) do
      {:ok, page} ->
        reduce_pages(access_token, page, acc, fun, 1)

      {:error, {:api_http, 409, body}} ->
        if cursor_reset?(body) do
          {:error, :cursor_reset}
        else
          {:error, {:api_http, 409, body}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reduce_pages(access_token, %{"entries" => entries} = page, acc, fun, page_n) do
    acc = Enum.reduce(entries, acc, fun)
    cursor = page["cursor"]

    if rem(page_n, 10) == 1 or page["has_more"] in [false, nil] do
      Logger.info(
        "Dropbox list page=#{page_n} entries=#{length(entries)} has_more=#{inspect(page["has_more"])}"
      )
    end

    case page do
      %{"has_more" => true, "cursor" => next_cursor} ->
        case list_folder_continue(access_token, next_cursor) do
          {:ok, next} ->
            reduce_pages(access_token, next, acc, fun, page_n + 1)

          {:error, {:api_http, 409, body}} ->
            if cursor_reset?(body),
              do: {:error, :cursor_reset},
              else: {:error, {:api_http, 409, body}}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:ok, {acc, cursor}}
    end
  end

  defp cursor_reset?(body) when is_map(body) do
    get_in(body, ["error", ".tag"]) == "reset" or
      (is_binary(body["error_summary"]) and String.starts_with?(body["error_summary"], "reset"))
  end

  defp cursor_reset?(body) when is_binary(body) do
    String.contains?(body, "\"reset\"") or String.contains?(body, "reset/")
  end

  defp cursor_reset?(_), do: false

  def download(access_token, path) when is_binary(path) do
    arg = Jason.encode!(%{"path" => path})

    case Req.post(@content <> "/files/download",
           headers: [
             {"authorization", "Bearer " <> access_token},
             {"dropbox-api-arg", arg}
           ],
           decode_body: false,
           receive_timeout: @recv_timeout
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
      ],
      receive_timeout: @recv_timeout
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
