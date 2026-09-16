defmodule EagleDropboxViewer.Library.DropboxLiveTest do
  use EagleDropboxViewer.DataCase

  alias EagleDropboxViewer.Library
  alias EagleDropboxViewer.Library.{DropboxLive, FolderCursor, Item}
  alias EagleDropboxViewer.Repo

  setup do
    DropboxLive.ensure_cache!()
    :ets.delete_all_objects(:eagle_dropbox_live_folders)
    :ok
  end

  test "recent_page reads immediately from Postgres without Dropbox" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    for {id, btime} <- [{"A", 300}, {"B", 100}, {"C", 200}] do
      %Item{}
      |> Item.changeset(%{
        id: id,
        name: id,
        ext: "jpg",
        tags: [],
        folders: [],
        btime: btime,
        mtime: btime,
        has_thumb: true,
        inserted_at: now,
        updated_at: now
      })
      |> Repo.insert!()
    end

    assert {:ok, page} = DropboxLive.recent_page(1, 2)
    assert page.source == :db
    assert Enum.map(page.items, & &1.id) == ["A", "C"]
    assert page.total == 3
    assert page.total_pages == 2
  end

  test "intake_page filters empty folders from Postgres" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    for {id, folders} <- [{"in", []}, {"out", ["F1"]}] do
      %Item{}
      |> Item.changeset(%{
        id: id,
        name: id,
        ext: "png",
        tags: [],
        folders: folders,
        btime: 1,
        has_thumb: true,
        inserted_at: now,
        updated_at: now
      })
      |> Repo.insert!()
    end

    assert {:ok, page} = DropboxLive.intake_page(1, 60)
    assert Enum.map(page.items, & &1.id) == ["in"]
    assert page.source == :db_intake
  end

  test "folder cursor can be persisted and cleared" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert :error = DropboxLive.get_cursor()

    %FolderCursor{}
    |> FolderCursor.changeset(%{
      id: "images",
      path: "/lib/images",
      cursor: "cursor-abc",
      inserted_at: now,
      updated_at: now
    })
    |> Repo.insert!()

    assert {:ok, %FolderCursor{cursor: "cursor-abc"}} = DropboxLive.get_cursor()

    assert :ok = DropboxLive.clear_cursor!()
    assert :error = DropboxLive.get_cursor()
  end

  test "refresh without Dropbox connection returns not_connected" do
    assert {:error, :not_connected} = Library.refresh_recent_from_dropbox()
    assert {:error, :not_connected} = Library.refresh_recent_from_dropbox(force: true)
  end

  test "Library.view_page recent uses DropboxLive db source" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Item{}
    |> Item.changeset(%{
      id: "X1",
      name: "x",
      ext: "jpg",
      tags: [],
      folders: [],
      btime: 9,
      has_thumb: true,
      inserted_at: now,
      updated_at: now
    })
    |> Repo.insert!()

    page = Library.view_page("recent", 1)
    assert page.source == :db
    assert Enum.map(page.items, & &1.id) == ["X1"]
  end
end
