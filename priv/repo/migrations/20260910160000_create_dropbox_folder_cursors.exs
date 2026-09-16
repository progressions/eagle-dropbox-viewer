defmodule EagleDropboxViewer.Repo.Migrations.CreateDropboxFolderCursors do
  use Ecto.Migration

  def change do
    create table(:dropbox_folder_cursors, primary_key: false) do
      add :id, :string, primary_key: true
      add :path, :string, null: false
      add :cursor, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:eagle_items, [:btime])
  end
end
