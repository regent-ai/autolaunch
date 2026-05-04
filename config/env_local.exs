defmodule Autolaunch.ConfigEnvLocal do
  @env_local_path Path.expand("../.env.local", __DIR__)

  def fetch(key, default \\ "") do
    System.get_env(key) || Map.get(values(), key, default)
  end

  def fetch_required(key) do
    case fetch(key, "") do
      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> raise_missing!(key)
          trimmed -> trimmed
        end

      _ ->
        raise_missing!(key)
    end
  end

  def values do
    case File.read(@env_local_path) do
      {:ok, contents} ->
        contents
        |> String.split("\n")
        |> Enum.reduce(%{}, fn line, acc ->
          case parse_line(line) do
            {key, value} -> Map.put(acc, key, value)
            nil -> acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp parse_line(line) do
    trimmed = String.trim(line)

    if trimmed == "" or String.starts_with?(trimmed, "#") do
      nil
    else
      normalized =
        if String.starts_with?(trimmed, "export ") do
          trimmed |> String.replace_prefix("export ", "") |> String.trim()
        else
          trimmed
        end

      case String.split(normalized, "=", parts: 2) do
        [key, value] ->
          {
            String.trim(key),
            value
            |> String.trim()
            |> String.trim_leading("\"")
            |> String.trim_trailing("\"")
            |> String.trim_leading("'")
            |> String.trim_trailing("'")
          }

        _ ->
          nil
      end
    end
  end

  defp raise_missing!(key) do
    raise """
    environment variable #{key} is missing or blank.
    """
  end
end
