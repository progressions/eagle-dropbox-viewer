defmodule EagleDropboxViewer.LibraryTest do
  use EagleDropboxViewer.DataCase

  alias EagleDropboxViewer.Library

  test "apply_index upserts items and sync row" do
    index = %{
      "version" => 2,
      "built_at" => "2026-01-01T00:00:00Z",
      "updated_at" => "2026-01-02T00:00:00Z",
      "items" => [
        %{
          "id" => "ABC123",
          "name" => "sample",
          "ext" => "png",
          "tags" => ["eunbi"],
          "folders" => [],
          "mtime" => 1_700_000_000_000,
          "btime" => 1_700_000_000_000,
          "w" => 1024,
          "h" => 1024,
          "size" => 12,
          "has_thumb" => true
        }
      ]
    }

    assert {:ok, sync} = Library.apply_index(index)
    assert sync.item_count == 1
    assert Library.item_count() == 1

    item = Library.get_item("ABC123")
    assert item.name == "sample"
    assert item.has_thumb
    assert item.tags == ["eunbi"]

    assert [recent] = Library.recent_page(1)
    assert recent.id == "ABC123"
  end
end
