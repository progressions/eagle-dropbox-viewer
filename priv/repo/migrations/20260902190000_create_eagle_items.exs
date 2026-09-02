defmodule EagleDropboxViewer.Repo.Migrations.CreateEagleItems do
  use Ecto.Migration

  def change do
    create table(:library_syncs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :index_version, :integer
      add :built_at, :string
      add :index_updated_at, :string
      add :item_count, :integer, null: false, default: 0
      add :synced_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:eagle_items, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :ext, :string
      add :tags, {:array, :string}, null: false, default: []
      add :folders, {:array, :string}, null: false, default: []
      add :mtime, :bigint
      add :btime, :bigint
      add :width, :integer
      add :height, :integer
      add :size, :bigint
      add :has_thumb, :boolean, null: false, default: false
      add :duration, :float

      timestamps(type: :utc_datetime)
    end

    create index(:eagle_items, [:mtime])
    create index(:eagle_items, [:ext])
  end
end
