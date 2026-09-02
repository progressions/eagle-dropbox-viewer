defmodule EagleDropboxViewer.Dropbox do
  @moduledoc """
  Context for Dropbox OAuth connections and read-only API helpers.
  """

  import Ecto.Query, warn: false

  alias EagleDropboxViewer.Repo
  alias EagleDropboxViewer.Dropbox.{Client, Connection, OAuth, TokenCrypto}

  def library_path do
    Application.get_env(:eagle_dropbox_viewer, :dropbox_library_path) ||
      "/ISAAC/GENNIE/Eunbi.library"
  end

  def get_connection do
    Connection
    |> order_by([c], desc: c.updated_at)
    |> limit(1)
    |> Repo.one()
  end

  def connected?, do: not is_nil(get_connection())

  def delete_connection do
    case get_connection() do
      nil -> :ok
      conn -> Repo.delete(conn)
    end
  end

  def upsert_from_oauth(token_payload) do
    with {:ok, account} <- Client.get_current_account(token_payload.access_token),
         {:ok, attrs} <- build_attrs(token_payload, account) do
      case get_connection() do
        nil ->
          %Connection{}
          |> Connection.changeset(attrs)
          |> Repo.insert()

        existing ->
          existing
          |> Connection.changeset(attrs)
          |> Repo.update()
      end
    end
  end

  def with_access_token(fun) when is_function(fun, 1) do
    case get_connection() do
      nil ->
        {:error, :not_connected}

      connection ->
        with {:ok, access_token} <- ensure_access_token(connection) do
          fun.(access_token)
        end
    end
  end

  def list_library_entries(limit \\ 25) do
    with_access_token(fn token ->
      Client.list_folder(token, library_path(), limit: limit)
    end)
  end

  def ensure_access_token(%Connection{} = connection) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    skew = DateTime.add(now, 60, :second)

    cond do
      DateTime.compare(connection.access_token_expires_at, skew) == :gt ->
        TokenCrypto.decrypt(connection.access_token_ciphertext)

      true ->
        refresh_connection(connection)
    end
  end

  defp refresh_connection(%Connection{} = connection) do
    with {:ok, refresh_token} <- TokenCrypto.decrypt(connection.refresh_token_ciphertext),
         {:ok, payload} <- OAuth.refresh_access_token(refresh_token),
         {:ok, updated} <- persist_refreshed(connection, payload) do
      TokenCrypto.decrypt(updated.access_token_ciphertext)
    end
  end

  defp persist_refreshed(%Connection{} = connection, payload) do
    refresh_ciphertext =
      case payload.refresh_token do
        token when is_binary(token) and token != "" -> TokenCrypto.encrypt(token)
        _ -> connection.refresh_token_ciphertext
      end

    attrs = %{
      access_token_ciphertext: TokenCrypto.encrypt(payload.access_token),
      refresh_token_ciphertext: refresh_ciphertext,
      access_token_expires_at: payload.expires_at,
      scopes: payload.scopes || connection.scopes
    }

    connection
    |> Connection.changeset(attrs)
    |> Repo.update()
  end

  defp build_attrs(token_payload, account) do
    unless is_binary(token_payload.refresh_token) and token_payload.refresh_token != "" do
      raise "Dropbox did not return a refresh_token; ensure token_access_type=offline"
    end

    name =
      get_in(account, ["name", "display_name"]) ||
        get_in(account, ["name", "familiar_name"])

    {:ok,
     %{
       account_id: token_payload.account_id || account["account_id"],
       account_email: account["email"],
       display_name: name,
       access_token_ciphertext: TokenCrypto.encrypt(token_payload.access_token),
       refresh_token_ciphertext: TokenCrypto.encrypt(token_payload.refresh_token),
       access_token_expires_at: token_payload.expires_at,
       scopes: token_payload.scopes
     }}
  end
end
