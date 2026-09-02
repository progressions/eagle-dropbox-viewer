defmodule EagleDropboxViewer.Repo.Migrations.CreateDropboxConnections do
  use Ecto.Migration

  def change do
    create table(:dropbox_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, :string, null: false
      add :account_email, :string
      add :display_name, :string
      add :access_token_ciphertext, :text, null: false
      add :refresh_token_ciphertext, :text, null: false
      add :access_token_expires_at, :utc_datetime, null: false
      add :scopes, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:dropbox_connections, [:account_id])
  end
end
