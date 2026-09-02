defmodule EagleDropboxViewer.Dropbox.Connection do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dropbox_connections" do
    field :account_id, :string
    field :account_email, :string
    field :display_name, :string
    field :access_token_ciphertext, :string
    field :refresh_token_ciphertext, :string
    field :access_token_expires_at, :utc_datetime
    field :scopes, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :account_id,
      :account_email,
      :display_name,
      :access_token_ciphertext,
      :refresh_token_ciphertext,
      :access_token_expires_at,
      :scopes
    ])
    |> validate_required([
      :account_id,
      :access_token_ciphertext,
      :refresh_token_ciphertext,
      :access_token_expires_at
    ])
    |> unique_constraint(:account_id)
  end
end
