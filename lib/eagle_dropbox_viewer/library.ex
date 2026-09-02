defmodule EagleDropboxViewer.Library do
  @moduledoc """
  Eagle library metadata synced from Dropbox `phone-index.json`.
  """

  import Ecto.Query, warn: false

  alias EagleDropboxViewer.Dropbox
  alias EagleDropboxViewer.Dropbox.Client
  alias EagleDropboxViewer.Library.{Item, Sync}
  alias EagleDropboxViewer.Repo

  @page_size 60

  def page_size, do: @page_size

  def item_count do
    Repo.aggregate(Item, :count)
  end

  def latest_sync do
    Sync
    |> order_by([s], desc: s.synced_at)
    |> limit(1)
    |> Repo.one()
  end

  def get_item(id) when is_binary(id), do: Repo.get(Item, id)

  def recent_page(page \\ 1) when is_integer(page) and page >= 1 do
    offset = (page - 1) * @page_size

    Item
    |> order_by([i], desc: i.mtime)
    |> limit(^@page_size)
    |> offset(^offset)
    |> Repo.all()
  end

  def total_pages do
    count = item_count()
    if count == 0, do: 1, else: div(count + @page_size - 1, @page_size)
  end

  def original_path(%Item{} = item) do
    Path.join([
      Dropbox.library_path(),
      "images",
      item.id <> ".info",
      item.name <> "." <> (item.ext || "")
    ])
  end

  def thumb_path(%Item{} = item) do
    base = Path.join([Dropbox.library_path(), "images", item.id <> ".info"])
    stem = item.name

    Enum.map(["png", "jpg", "webp"], fn ext ->
      Path.join(base, "#{stem}_thumbnail.#{ext}")
    end)
  end

  def sync_from_dropbox do
    Dropbox.with_access_token(fn token ->
      path = Path.join(Dropbox.library_path(), "phone-index.json")

      with {:ok, body} <- Client.download(token, path),
           {:ok, index} <- Jason.decode(body) do
        apply_index(index)
      end
    end)
  end

  def apply_index(%{"items" => items} = index) when is_list(items) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      Repo.delete_all(Item)

      items
      |> Enum.chunk_every(500)
      |> Enum.each(fn chunk ->
        rows =
          chunk
          |> Enum.map(&row_from_index_item(&1, now))
          |> Enum.reject(&is_nil/1)

        if rows != [] do
          Repo.insert_all(Item, rows)
        end
      end)

      sync_attrs = %{
        index_version: index["version"],
        built_at: index["built_at"],
        index_updated_at: index["updated_at"],
        item_count: length(items),
        synced_at: now
      }

      %Sync{}
      |> Sync.changeset(sync_attrs)
      |> Repo.insert!()
    end)
    |> case do
      {:ok, sync} -> {:ok, sync}
      {:error, reason} -> {:error, reason}
    end
  end

  def apply_index(_), do: {:error, :invalid_index}

  defp row_from_index_item(%{"id" => id, "name" => name} = item, now)
       when is_binary(id) and is_binary(name) do
    %{
      id: id,
      name: name,
      ext: item["ext"],
      tags: List.wrap(item["tags"]),
      folders: List.wrap(item["folders"]) |> Enum.map(&to_string/1),
      mtime: item["mtime"],
      btime: item["btime"],
      width: item["w"],
      height: item["h"],
      size: item["size"],
      has_thumb: item["has_thumb"] == true,
      duration: item["duration"],
      inserted_at: now,
      updated_at: now
    }
  end

  defp row_from_index_item(_, _), do: nil
end
