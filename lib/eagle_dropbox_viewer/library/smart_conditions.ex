defmodule EagleDropboxViewer.Library.SmartConditions do
  @moduledoc """
  Eagle smart-folder rule evaluation (same semantics as eagle-browse/library.py).
  """

  @image_exts MapSet.new(~w(jpg jpeg png webp gif bmp tif tiff heic avif))
  @video_exts MapSet.new(~w(mp4 mov webm mkv m4v avi))
  @audio_exts MapSet.new(~w(mp3 wav m4a aac flac ogg))

  def eval_conditions(_item, nil), do: true
  def eval_conditions(_item, []), do: true

  def eval_conditions(item, conditions) when is_list(conditions) do
    Enum.all?(conditions, &eval_group(item, &1))
  end

  defp eval_group(item, group) when is_map(group) do
    rules = group["rules"] || []
    match = String.upcase(to_string(group["match"] || "AND"))
    boolean = String.upcase(to_string(group["boolean"] || "TRUE"))

    ok =
      cond do
        rules == [] -> true
        match == "OR" -> Enum.any?(rules, &eval_rule(item, &1))
        true -> Enum.all?(rules, &eval_rule(item, &1))
      end

    if boolean == "FALSE", do: not ok, else: ok
  end

  defp eval_rule(item, rule) when is_map(rule) do
    eval_rule(item, rule["property"], rule["method"], rule["value"])
  end

  defp eval_rule(item, property, method, value) do
    method = String.downcase(to_string(method || ""))
    prop = String.downcase(to_string(property || ""))

    case prop do
      "tags" ->
        vals = MapSet.new(as_str_list(value))
        tags = MapSet.new(item.tags || [])
        set_rule(tags, vals, method)

      "folders" ->
        vals = MapSet.new(as_str_list(value))
        folders = MapSet.new(item.folders || [])
        set_rule(folders, vals, method)

      "type" ->
        ok = type_matches?(item.ext, value)
        case method do
          "equal" -> ok
          "unequal" -> not ok
          m when m in ~w(intersection union) -> ok
          "identity" -> not ok
          _ -> false
        end

      "name" ->
        name = String.downcase(item.name || "")
        v = String.downcase(to_string(value))
        case method do
          "contain" -> String.contains?(name, v)
          "uncontain" -> not String.contains?(name, v)
          "equal" -> name == v
          "unequal" -> name != v
          _ -> false
        end

      "rating" ->
        star = item.star || 0
        case Integer.parse(to_string(value)) do
          {target, _} ->
            case method do
              "equal" -> star == target
              "unequal" -> star != target
              m when m in ~w(gt greater) -> star > target
              m when m in ~w(lt less) -> star < target
              m when m in ~w(gte ge) -> star >= target
              m when m in ~w(lte le) -> star <= target
              _ -> false
            end
          :error -> false
        end

      _ ->
        false
    end
  end

  defp set_rule(have, want, method) do
    case method do
      m when m in ~w(intersection union) -> not MapSet.disjoint?(have, want)
      m when m in ~w(subset contain all) -> want != MapSet.new() and MapSet.subset?(want, have)
      "identity" -> MapSet.disjoint?(have, want)
      "equal" -> have == want
      "unequal" -> have != want
      _ -> false
    end
  end

  defp type_matches?(ext, value) do
    v = value |> to_string() |> String.downcase() |> String.trim_leading(".")
    e = (ext || "") |> String.downcase() |> String.trim_leading(".")

    cond do
      v == "video" -> MapSet.member?(@video_exts, e)
      v == "audio" -> MapSet.member?(@audio_exts, e)
      v in ~w(image img photo) -> MapSet.member?(@image_exts, e)
      true -> e == v
    end
  end

  defp as_str_list(value) when is_list(value), do: Enum.map(value, &to_string/1)
  defp as_str_list(value) when is_binary(value), do: [value]
  defp as_str_list(value) when is_integer(value), do: [Integer.to_string(value)]
  defp as_str_list(_), do: []
end
