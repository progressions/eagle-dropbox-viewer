defmodule EagleDropboxViewer.Library.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "eagle_items" do
    field :name, :string
    field :ext, :string
    field :tags, {:array, :string}, default: []
    field :folders, {:array, :string}, default: []
    field :mtime, :integer
    field :btime, :integer
    field :width, :integer
    field :height, :integer
    field :size, :integer
    field :has_thumb, :boolean, default: false
    field :duration, :float

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :id,
      :name,
      :ext,
      :tags,
      :folders,
      :mtime,
      :btime,
      :width,
      :height,
      :size,
      :has_thumb,
      :duration
    ])
    |> validate_required([:id, :name])
  end
end
