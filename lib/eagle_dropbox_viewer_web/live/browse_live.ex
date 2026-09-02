defmodule EagleDropboxViewerWeb.BrowseLive do
  use EagleDropboxViewerWeb, :live_view

  alias EagleDropboxViewer.Library

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Browse")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    page = parse_page(params["page"])
    items = Library.recent_page(page)
    total_pages = Library.total_pages()
    sync = Library.latest_sync()

    socket
    |> assign(:page_title, "Browse")
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
    |> assign(:items, items)
    |> assign(:item, nil)
    |> assign(:sync, sync)
    |> assign(:item_count, Library.item_count())
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    case Library.get_item(id) do
      nil ->
        socket
        |> put_flash(:error, "Item not found")
        |> push_navigate(to: ~p"/browse")

      item ->
        socket
        |> assign(:page_title, item.name)
        |> assign(:item, item)
        |> assign(:items, [])
        |> assign(:page, 1)
        |> assign(:total_pages, 1)
        |> assign(:sync, Library.latest_sync())
        |> assign(:item_count, Library.item_count())
    end
  end

  defp parse_page(nil), do: 1

  defp parse_page(raw) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> n
      _ -> 1
    end
  end

  defp format_duration(nil), do: nil

  defp format_duration(seconds) when is_number(seconds) do
    total = trunc(seconds)
    m = div(total, 60)
    s = rem(total, 60)
    "#{m}:#{String.pad_leading(Integer.to_string(s), 2, "0")}"
  end

  defp video_ext?(ext) when is_binary(ext) do
    String.downcase(ext) in ~w(mp4 mov webm mkv)
  end

  defp video_ext?(_), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl px-4 py-8">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Browse</h1>
          <p class="text-sm text-base-content/70">
            <%= if @item_count > 0 do %>
              {@item_count} items
              <%= if @sync do %>
                · synced {Calendar.strftime(@sync.synced_at, "%Y-%m-%d %H:%M UTC")}
              <% end %>
            <% else %>
              No index yet — sync from <.link navigate={~p"/settings"} class="link">Settings</.link>.
            <% end %>
          </p>
        </div>
        <div class="flex gap-2">
          <.link navigate={~p"/settings"} class="btn btn-ghost btn-sm">Settings</.link>
          <%= if @item do %>
            <.link navigate={~p"/browse"} class="btn btn-ghost btn-sm">Back to grid</.link>
          <% end %>
        </div>
      </div>

      <%= if @item do %>
        <div class="mt-8 grid gap-6 lg:grid-cols-2">
          <div class="rounded-box border border-base-300 bg-base-200 p-2">
            <%= if video_ext?(@item.ext) do %>
              <video
                src={~p"/media/original/#{@item.id}"}
                controls
                class="max-h-[70vh] w-full rounded-box bg-black"
              />
            <% else %>
              <img
                src={~p"/media/original/#{@item.id}"}
                alt={@item.name}
                class="max-h-[70vh] w-full rounded-box object-contain"
              />
            <% end %>
          </div>
          <div class="space-y-3 text-sm">
            <h2 class="text-lg font-medium break-all">{@item.name}</h2>
            <p><span class="opacity-70">Eagle id</span> <code class="text-xs">{@item.id}</code></p>
            <p><span class="opacity-70">Type</span> {@item.ext || "?"}</p>
            <%= if @item.width && @item.height do %>
              <p><span class="opacity-70">Size</span> {@item.width}×{@item.height}</p>
            <% end %>
            <%= if @item.duration do %>
              <p><span class="opacity-70">Duration</span> {format_duration(@item.duration)}</p>
            <% end %>
            <div>
              <p class="opacity-70 mb-1">Tags</p>
              <div class="flex flex-wrap gap-1">
                <%= for tag <- @item.tags || [] do %>
                  <span class="badge badge-outline badge-sm">{tag}</span>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% else %>
        <div class="mt-8 grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
          <%= for item <- @items do %>
            <.link navigate={~p"/browse/#{item.id}"} class="group block">
              <div class="aspect-square overflow-hidden rounded-box bg-base-200 border border-base-300">
                <img
                  src={~p"/media/thumb/#{item.id}"}
                  alt={item.name}
                  loading="lazy"
                  class="h-full w-full object-cover transition group-hover:scale-[1.02]"
                />
              </div>
              <div class="mt-1 flex items-start justify-between gap-1">
                <p class="truncate text-xs">{item.name}</p>
                <%= if dur = format_duration(item.duration) do %>
                  <span class="badge badge-neutral badge-xs shrink-0">{dur}</span>
                <% end %>
              </div>
            </.link>
          <% end %>
        </div>

        <%= if @item_count > 0 do %>
          <div class="mt-8 flex items-center justify-center gap-3">
            <%= if @page > 1 do %>
              <.link patch={~p"/browse?page=#{@page - 1}"} class="btn btn-sm">Prev</.link>
            <% else %>
              <button class="btn btn-sm btn-disabled" disabled>Prev</button>
            <% end %>
            <span class="text-sm opacity-70">Page {@page} / {@total_pages}</span>
            <%= if @page < @total_pages do %>
              <.link patch={~p"/browse?page=#{@page + 1}"} class="btn btn-sm">Next</.link>
            <% else %>
              <button class="btn btn-sm btn-disabled" disabled>Next</button>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
