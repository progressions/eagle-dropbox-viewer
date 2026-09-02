defmodule EagleDropboxViewer.LibraryTest do
  use EagleDropboxViewer.DataCase

  alias EagleDropboxViewer.Library
  alias EagleDropboxViewer.Library.SmartConditions

  test "apply_index upserts items and sync row" do
    index = %{
      "version" => 2,
      "built_at" => "2026-01-01T00:00:00Z",
      "updated_at" => "2026-01-02T00:00:00Z",
      "smart_folders" => [
        %{
          "id" => "SFM",
          "name" => "Music",
          "conditions" => [
            %{
              "match" => "AND",
              "boolean" => "TRUE",
              "rules" => [
                %{"property" => "tags", "method" => "union", "value" => ["music"]}
              ]
            }
          ],
          "inherited" => [
            %{
              "match" => "AND",
              "boolean" => "TRUE",
              "rules" => [
                %{"property" => "tags", "method" => "union", "value" => ["music"]}
              ]
            }
          ],
          "children" => []
        },
        %{
          "id" => "SF1",
          "name" => "Eunbi",
          "conditions" => [
            %{
              "match" => "AND",
              "boolean" => "TRUE",
              "rules" => [
                %{"property" => "tags", "method" => "union", "value" => ["eunbi"]}
              ]
            }
          ],
          "inherited" => [
            %{
              "match" => "AND",
              "boolean" => "TRUE",
              "rules" => [
                %{"property" => "tags", "method" => "union", "value" => ["eunbi"]}
              ]
            }
          ],
          "children" => []
        }
      ],
      "folders" => [%{"id" => "F1", "name" => "MUSIC", "tags" => [], "children" => []}],
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
          "has_thumb" => true,
          "star" => 4
        },
        %{
          "id" => "OTHER",
          "name" => "other",
          "ext" => "jpg",
          "tags" => ["music"],
          "folders" => ["F1"],
          "mtime" => 1_700_000_000_100,
          "has_thumb" => false
        }
      ]
    }

    assert {:ok, sync} = Library.apply_index(index)
    assert sync.item_count == 2
    assert Library.item_count() == 2

    item = Library.get_item("ABC123")
    assert item.star == 4
    assert item.folders == []

    nav = Library.nav_entries()
    eunbi = Enum.find(nav, &(&1.key == "eunbi"))
    assert eunbi.resolved_id == "SF1"

    intake = Library.view_page("intake", 1)
    assert Enum.map(intake.items, & &1.id) == ["ABC123"]

    eunbi_page = Library.view_page("eunbi", 1)
    assert Enum.map(eunbi_page.items, & &1.id) == ["ABC123"]

    music = Library.view_page("music", 1)
    assert Enum.map(music.items, & &1.id) == ["OTHER"]
  end

  test "smart conditions tag union and rating unequal" do
    item = %EagleDropboxViewer.Library.Item{
      id: "1",
      name: "x",
      tags: ["eunbi"],
      folders: [],
      star: 4
    }

    conditions = [
      %{
        "match" => "AND",
        "boolean" => "TRUE",
        "rules" => [
          %{"property" => "tags", "method" => "union", "value" => ["eunbi"]},
          %{"property" => "rating", "method" => "unequal", "value" => "1"}
        ]
      }
    ]

    assert SmartConditions.eval_conditions(item, conditions)

    refute SmartConditions.eval_conditions(%{item | star: 1}, conditions)
  end
end
