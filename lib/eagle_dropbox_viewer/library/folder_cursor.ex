defmodule EagleDropboxViewer.Library.FolderCursor do
  @moduledoc """
  Persisted Dropbox `list_folder` cursor for incremental (delta) sync of `images/`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "dropbox_folder_cursors" do
    field :path, :string
    field :cursor, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:id, :path, :cursor, :inserted_at, :updated_at])
    |> validate_required([:id, :path, :cursor])
  end
end
