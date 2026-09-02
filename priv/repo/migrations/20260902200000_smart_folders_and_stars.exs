defmodule EagleDropboxViewer.Repo.Migrations.SmartFoldersAndStars do
  use Ecto.Migration

  def change do
    alter table(:eagle_items) do
      add :star, :integer
    end

    alter table(:library_syncs) do
      add :smart_folders, :map
      add :folders, :map
    end
  end
end
