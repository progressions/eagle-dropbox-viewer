defmodule EagleDropboxViewer.Library.Sync do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "library_syncs" do
    field :index_version, :integer
    field :built_at, :string
    field :index_updated_at, :string
    field :item_count, :integer, default: 0
    field :synced_at, :utc_datetime
    field :smart_folders, :map
    field :folders, :map

    timestamps(type: :utc_datetime)
  end

  def changeset(sync, attrs) do
    sync
    |> cast(attrs, [
      :index_version,
      :built_at,
      :index_updated_at,
      :item_count,
      :synced_at,
      :smart_folders,
      :folders
    ])
    |> validate_required([:item_count, :synced_at])
  end
end
