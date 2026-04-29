defmodule Autolaunch.LocalCache do
  @moduledoc false

  @cache_name :autolaunch_cache

  def child_spec, do: RegentCache.child_spec(@cache_name)
  def status, do: RegentCache.status(@cache_name)

  def fetch(key, ttl_seconds, fun) do
    case RegentCache.fetch(@cache_name, key, ttl_seconds, fun) do
      {:ok, value} -> {:ok, restore_known_keys(value)}
      other -> other
    end
  end

  def delete(keys), do: RegentCache.delete(@cache_name, keys)
  def get_string(key), do: RegentCache.get_string(@cache_name, key)
  def increment(key, ttl_seconds), do: RegentCache.increment(@cache_name, key, ttl_seconds)

  defp restore_known_keys(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {restore_key(key), restore_known_keys(item)} end)
  end

  defp restore_known_keys(value) when is_list(value), do: Enum.map(value, &restore_known_keys/1)
  defp restore_known_keys(value), do: value

  defp restore_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp restore_key(key), do: key
end
