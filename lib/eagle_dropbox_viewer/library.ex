defmodule EagleDropboxViewer.Library do
  @moduledoc """
  Eagle library metadata synced from Dropbox `phone-index.json`.
  """

  import Ecto.Query, warn: false

  alias EagleDropboxViewer.Dropbox
  alias EagleDropboxViewer.Dropbox.Client
  alias EagleDropboxViewer.Library.{Item, SmartConditions, Sync}
  alias EagleDropboxViewer.Repo

  @page_size 60

  # Pinned sidebar entries (resolved by name from the last sync).
  @pinned [
    %{key: "intake", label: "Intake", kind: :intake},
    %{key: "eunbi", label: "Eunbi", kind: :smart, name: "Eunbi"},
    %{key: "sofie", label: "Sofie", kind: :smart, name: "Sofie"},
    %{key: "shadow-kingdom", label: "Shadow Kingdom", kind: :smart, name: "Shadow Kingdom"},
    %{key: "movies", label: "Movies", kind: :smart, name: "Movies"},
    %{key: "music", label: "Music", kind: :folder, name: "MUSIC"}
  ]

  def page_size, do: @page_size
  def pinned_nav, do: @pinned

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

  def nav_entries do
    sync = latest_sync()
    smarts = flatten_smart_folders((sync && sync.smart_folders) || [])
    folders = flatten_folders((sync && sync.folders) || [])

    Enum.map(@pinned, fn entry ->
      case entry.kind do
        :intake ->
          Map.put(entry, :resolved_id, nil)

        :smart ->
          id =
            smarts
            |> Enum.find_value(fn {sf, _depth} ->
              if sf["name"] == entry.name, do: sf["id"]
            end)

          Map.merge(entry, %{resolved_id: id, node: Enum.find(smarts, fn {sf, _} -> sf["id"] == id end)})

        :folder ->
          id =
            folders
            |> Enum.find_value(fn {f, _depth} ->
              if String.downcase(f["name"] || "") == String.downcase(entry.name), do: f["id"]
            end)

          Map.put(entry, :resolved_id, id)
      end
    end)
  end

  def recent_page(page \\ 1) when is_integer(page) and page >= 1 do
    view_page("recent", page)
  end

  def view_page(view_key, page \\ 1) when is_binary(view_key) and is_integer(page) and page >= 1 do
    offset = (page - 1) * @page_size
    items = items_for_view(view_key)
    total = length(items)
    page_items = items |> Enum.drop(offset) |> Enum.take(@page_size)
    total_pages = if total == 0, do: 1, else: div(total + @page_size - 1, @page_size)

    %{items: page_items, total: total, total_pages: total_pages, page: page}
  end

  def items_for_view("recent") do
    Item
    |> order_by([i], desc: i.mtime)
    |> Repo.all()
  end

  def items_for_view("intake") do
    Item
    |> where([i], i.folders == [] or is_nil(i.folders))
    |> order_by([i], desc: i.mtime)
    |> Repo.all()
  end

  def items_for_view(view_key) when is_binary(view_key) do
    entry = Enum.find(nav_entries(), &(&1.key == view_key))

    cond do
      is_nil(entry) ->
        []

      entry.kind == :smart and entry.resolved_id ->
        sync = latest_sync()
        smarts = flatten_smart_folders((sync && sync.smart_folders) || [])

        case Enum.find(smarts, fn {sf, _} -> sf["id"] == entry.resolved_id end) do
          {sf, _} ->
            conditions = sf["inherited"] || sf["conditions"] || []

            Item
            |> order_by([i], desc: i.mtime)
            |> Repo.all()
            |> Enum.filter(&SmartConditions.eval_conditions(&1, conditions))

          nil ->
            []
        end

      entry.kind == :folder and entry.resolved_id ->
        folder_id = entry.resolved_id

        Item
        |> where([i], ^folder_id in i.folders)
        |> order_by([i], desc: i.mtime)
        |> Repo.all()

      true ->
        []
    end
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
        synced_at: now,
        smart_folders: %{"roots" => index["smart_folders"] || []},
        folders: %{"roots" => index["folders"] || []}
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

  def flatten_smart_folders(%{"roots" => roots}) when is_list(roots), do: flatten_smart_folders(roots)
  def flatten_smart_folders(nodes) when is_list(nodes), do: walk_nodes(nodes, 0)
  def flatten_smart_folders(_), do: []

  def flatten_folders(%{"roots" => roots}) when is_list(roots), do: flatten_folders(roots)
  def flatten_folders(nodes) when is_list(nodes), do: walk_nodes(nodes, 0)
  def flatten_folders(_), do: []

  defp walk_nodes(nodes, depth) do
    Enum.flat_map(nodes, fn
      node when is_map(node) ->
        [{node, depth} | walk_nodes(node["children"] || [], depth + 1)]

      _ ->
        []
    end)
  end

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
      star: item["star"],
      inserted_at: now,
      updated_at: now
    }
  end

  defp row_from_index_item(_, _), do: nil
end
