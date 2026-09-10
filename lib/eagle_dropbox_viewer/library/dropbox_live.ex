defmodule EagleDropboxViewer.Library.DropboxLive do
  @moduledoc """
  Live Dropbox sync for phone Browse Recent / Intake.

  Browse always reads from Postgres immediately. Background refresh uses a
  persisted Dropbox `list_folder` cursor (`list_folder/continue` deltas) so a
  normal visit does **not** recursively walk the whole `images/` tree.

  Full recursive listing only when:
  - no cursor and the Items table is empty, or
  - cursor is invalid/reset, or
  - Settings force refresh (`force: true`).

  When Items already exist (e.g. from phone-index) and there is no cursor yet,
  we seed via `get_latest_cursor` (one API call) and skip the walk.
  """

  require Logger

  import Ecto.Query

  alias EagleDropboxViewer.Dropbox
  alias EagleDropboxViewer.Dropbox.Client
  alias EagleDropboxViewer.Library.{FolderCursor, Item}
  alias EagleDropboxViewer.Repo

  @cache_table :eagle_dropbox_live_folders
  @cursor_id "images"
  @meta_concurrency 8
  @candidate_k 200
  @recent_window 200

  def ensure_cache! do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ets.new(@cache_table, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        :ok
    end
  end

  @doc """
  Recent page — always from Postgres (never blocks on Dropbox).
  """
  def recent_page(page, page_size) when is_integer(page) and page >= 1 do
    ensure_cache!()
    warm_ets_from_db_if_empty()
    db_recent_page(page, page_size)
  end

  @doc """
  Intake page — always from Postgres.
  """
  def intake_page(page, page_size) when is_integer(page) and page >= 1 do
    ensure_cache!()
    warm_ets_from_db_if_empty()
    db_intake_page(page, page_size)
  end

  @doc """
  Refresh from Dropbox using deltas when possible.

  Options:
  - `:force` — clear cursor and do a full recursive top-K rebuild
  """
  def refresh_latest_cache(opts \\ []) do
    ensure_cache!()
    force? = Keyword.get(opts, :force, false)

    case :ets.insert_new(@cache_table, {:refresh_lock, System.monotonic_time(:millisecond)}) do
      false ->
        Logger.info("DropboxLive refresh skipped — already running")
        {:ok, :already_running}

      true ->
        try do
          do_refresh(force?)
        after
          :ets.delete(@cache_table, :refresh_lock)
        end
    end
  end

  def refresh_intake_cache(opts \\ []), do: refresh_latest_cache(opts)
  def refresh_folder_cache(opts \\ []), do: refresh_latest_cache(opts)

  def clear_cursor! do
    case Repo.get(FolderCursor, @cursor_id) do
      nil -> :ok
      row -> Repo.delete(row)
    end

    :ok
  end

  def get_cursor do
    case Repo.get(FolderCursor, @cursor_id) do
      %FolderCursor{cursor: cursor} = row when is_binary(cursor) and cursor != "" ->
        {:ok, row}

      _ ->
        :error
    end
  end

  def get_or_fetch_item(id) when is_binary(id) do
    case Repo.get(Item, id) do
      %Item{} = item ->
        {:ok, item}

      nil ->
        Dropbox.with_access_token(fn token ->
          folder = Path.join([Dropbox.library_path(), "images", id <> ".info"])

          with {:ok, meta} <- download_metadata(token, folder),
               {:ok, item} <- upsert_from_meta(meta, System.system_time(:millisecond)) do
            {:ok, item}
          end
        end)
    end
  end

  defp do_refresh(force?) do
    Dropbox.with_access_token(fn token ->
      images = Path.join(Dropbox.library_path(), "images")
      t0 = System.monotonic_time(:millisecond)

      result =
        cond do
          force? ->
            Logger.info("DropboxLive refresh mode=full_force path=#{images}")
            _ = clear_cursor!()
            full_rebuild(token, images)

          match?({:ok, _}, get_cursor()) ->
            {:ok, %FolderCursor{cursor: cursor}} = get_cursor()
            Logger.info("DropboxLive refresh mode=delta")
            delta_refresh(token, images, cursor)

          Repo.aggregate(Item, :count, :id) > 0 ->
            Logger.info("DropboxLive refresh mode=seed_latest_cursor (items present, skip walk)")
            seed_latest_cursor(token, images)

          true ->
            Logger.info("DropboxLive refresh mode=full_initial path=#{images}")
            full_rebuild(token, images)
        end

      elapsed = System.monotonic_time(:millisecond) - t0

      case result do
        {:ok, info} when is_map(info) ->
          rebuild_ets_recent_window()
          Logger.info("DropboxLive refresh done in #{elapsed}ms #{inspect(info)}")
          {:ok, Map.put(info, :elapsed_ms, elapsed)}

        other ->
          other
      end
    end)
  end

  defp seed_latest_cursor(token, images) do
    with {:ok, cursor} <- Client.get_latest_cursor(token, images, recursive: true),
         :ok <- save_cursor(images, cursor) do
      {:ok, %{mode: :seed_latest_cursor, pages: 0}}
    end
  end

  defp delta_refresh(token, images, cursor) do
    case Client.list_folder_continue_reduce(token, cursor, empty_delta_acc(), &collect_delta/2) do
      {:ok, {acc, new_cursor}} ->
        {:ok, hydrated} = hydrate_all(token, acc.changed)
        deleted = apply_deletes(acc.deleted)
        :ok = save_cursor(images, new_cursor)

        {:ok,
         %{
           mode: :delta,
           changed: length(acc.changed),
           hydrated: length(hydrated),
           deleted: deleted
         }}

      {:error, :cursor_reset} ->
        Logger.warning("DropboxLive cursor reset — falling back to full rebuild")
        _ = clear_cursor!()
        full_rebuild(token, images)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp full_rebuild(token, images) do
    case Client.list_folder_reduce(
           token,
           images,
           [limit: 2000, recursive: true],
           [],
           fn entry, acc ->
             case normalize_meta_file(entry) do
               nil -> acc
               folder -> top_k_push(acc, folder, @candidate_k)
             end
           end
         ) do
      {:ok, {candidates, cursor}} ->
        Logger.info("DropboxLive full candidates=#{length(candidates)} (top-#{@candidate_k})")
        {:ok, items} = hydrate_all(token, candidates)
        :ok = save_cursor(images, cursor)

        {:ok,
         %{
           mode: :full,
           candidates: length(candidates),
           hydrated: length(items)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp empty_delta_acc, do: %{changed: [], deleted: []}

  defp collect_delta(entry, acc) do
    case entry do
      %{".tag" => "deleted"} = del ->
        case deleted_item_id(del) do
          nil -> acc
          id -> %{acc | deleted: [id | acc.deleted]}
        end

      %{".tag" => "file", "name" => "metadata.json"} = file ->
        case normalize_meta_file(file) do
          nil -> acc
          folder -> %{acc | changed: top_k_push(acc.changed, folder, @candidate_k * 2)}
        end

      _ ->
        acc
    end
  end

  defp deleted_item_id(%{"path_display" => path}) when is_binary(path), do: id_from_path(path)
  defp deleted_item_id(%{"path_lower" => path}) when is_binary(path), do: id_from_path(path)
  defp deleted_item_id(_), do: nil

  defp id_from_path(path) do
    parts = path |> String.split("/") |> Enum.reject(&(&1 == ""))

    case Enum.reverse(parts) do
      ["metadata.json", info_dir | _] ->
        if String.ends_with?(info_dir, ".info"),
          do: String.replace_suffix(info_dir, ".info", ""),
          else: nil

      [info_dir | _] ->
        if String.ends_with?(info_dir, ".info"),
          do: String.replace_suffix(info_dir, ".info", ""),
          else: nil

      _ ->
        nil
    end
  end

  defp apply_deletes([]), do: 0

  defp apply_deletes(ids) do
    ids = ids |> Enum.uniq() |> Enum.reject(&is_nil/1)

    if ids == [] do
      0
    else
      {count, _} = Repo.delete_all(from(i in Item, where: i.id in ^ids))
      count
    end
  end

  defp save_cursor(_path, cursor) when not is_binary(cursor) or cursor == "", do: :ok

  defp save_cursor(path, cursor) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      id: @cursor_id,
      path: path,
      cursor: cursor,
      inserted_at: now,
      updated_at: now
    }

    %FolderCursor{}
    |> FolderCursor.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:path, :cursor, :updated_at]},
      conflict_target: :id
    )
    |> case do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp warm_ets_from_db_if_empty do
    case :ets.lookup(@cache_table, :recent) do
      [{:recent, items, _}] when is_list(items) and items != [] ->
        :ok

      _ ->
        rebuild_ets_recent_window()
    end
  end

  defp rebuild_ets_recent_window do
    items =
      Item
      |> order_by([i], desc: i.btime)
      |> limit(^@recent_window)
      |> Repo.all()

    :ets.insert(@cache_table, {:recent, items, System.monotonic_time(:millisecond)})
    :ok
  end

  defp db_recent_page(page, page_size) do
    total = Repo.aggregate(Item, :count, :id)
    total_pages = if total == 0, do: 1, else: div(total + page_size - 1, page_size)
    offset = (page - 1) * page_size

    items =
      Item
      |> order_by([i], desc: i.btime)
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    {:ok, %{items: items, total: total, total_pages: total_pages, page: page, source: :db}}
  end

  defp db_intake_page(page, page_size) do
    base = Item |> where([i], i.folders == [] or is_nil(i.folders))
    total = Repo.aggregate(base, :count, :id)
    total_pages = if total == 0, do: 1, else: div(total + page_size - 1, page_size)
    offset = (page - 1) * page_size

    items =
      base
      |> order_by([i], desc: i.btime)
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    {:ok, %{items: items, total: total, total_pages: total_pages, page: page, source: :db_intake}}
  end

  defp top_k_push(list, item, k) when length(list) < k do
    [item | list] |> Enum.sort_by(& &1.modified_ms, :desc)
  end

  defp top_k_push(list, item, _k) do
    oldest = List.last(list)

    if item.modified_ms > oldest.modified_ms do
      [item | Enum.drop(list, -1)] |> Enum.sort_by(& &1.modified_ms, :desc)
    else
      list
    end
  end

  defp hydrate_all(_token, []), do: {:ok, []}

  defp hydrate_all(token, candidates) do
    rows =
      candidates
      |> Task.async_stream(
        fn folder ->
          case Client.download(token, folder.meta_path) do
            {:ok, body} ->
              case Jason.decode(body) do
                {:ok, meta} -> upsert_from_meta(meta, folder.modified_ms)
                {:error, _} -> {:error, :json}
              end

            {:error, _} ->
              {:error, :meta}
          end
        end,
        max_concurrency: @meta_concurrency,
        timeout: 45_000,
        ordered: false
      )
      |> Enum.flat_map(fn
        {:ok, {:ok, item}} -> [item]
        _ -> []
      end)

    {:ok, rows}
  end

  defp normalize_meta_file(%{".tag" => "file", "name" => "metadata.json"} = entry) do
    path = entry["path_display"] || entry["path_lower"]

    if is_binary(path) do
      parts = path |> String.split("/") |> Enum.reject(&(&1 == ""))

      case Enum.reverse(parts) do
        ["metadata.json", info_dir | _] ->
          if String.ends_with?(info_dir, ".info") do
            id = String.replace_suffix(info_dir, ".info", "")
            folder_path = String.replace_suffix(path, "/metadata.json", "")

            %{
              id: id,
              path: folder_path,
              meta_path: path,
              modified_ms: parse_modified_ms(entry)
            }
          else
            nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp normalize_meta_file(_), do: nil

  defp parse_modified_ms(entry) do
    ts = entry["server_modified"] || entry["client_modified"]

    case is_binary(ts) && DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> DateTime.to_unix(dt, :millisecond)
      _ -> 0
    end
  end

  defp download_metadata(token, folder_path) do
    meta_path = Path.join(folder_path, "metadata.json")

    with {:ok, body} <- Client.download(token, meta_path),
         {:ok, meta} <- Jason.decode(body) do
      {:ok, meta}
    end
  end

  defp upsert_from_meta(%{"id" => id, "name" => name} = meta, modified_ms)
       when is_binary(id) and is_binary(name) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    btime = meta["btime"] || modified_ms || 0
    mtime = meta["mtime"] || meta["modificationTime"] || modified_ms || 0

    attrs = %{
      id: id,
      name: name,
      ext: meta["ext"],
      tags: List.wrap(meta["tags"]),
      folders: meta["folders"] |> List.wrap() |> Enum.map(&to_string/1),
      mtime: mtime,
      btime: btime,
      width: meta["width"] || meta["w"],
      height: meta["height"] || meta["h"],
      size: meta["size"],
      has_thumb: true,
      duration: meta["duration"],
      star: meta["star"],
      inserted_at: now,
      updated_at: now
    }

    case Repo.insert(
           Item.changeset(%Item{}, attrs),
           on_conflict: {:replace_all_except, [:id, :inserted_at]},
           conflict_target: :id
         ) do
      {:ok, item} -> {:ok, item}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp upsert_from_meta(_, _), do: {:error, :invalid_meta}
end
