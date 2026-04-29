defmodule Autolaunch.Prelaunch.AssetStorage do
  @moduledoc false

  @public_path "/prelaunch-assets"

  def persist(file_name, media_type, bytes)
      when is_binary(file_name) and is_binary(media_type) and is_binary(bytes) do
    asset_id = "asset_" <> Ecto.UUID.generate()
    ext = extension_for(media_type, file_name)
    stored_name = "#{asset_id}#{ext}"
    root_dir = root_dir!()
    absolute_path = Path.join(root_dir, stored_name)

    with :ok <- File.mkdir_p(root_dir),
         :ok <- File.write(absolute_path, bytes) do
      {:ok,
       %{
         asset_id: asset_id,
         storage_path: absolute_path,
         public_url: Path.join(@public_path, stored_name),
         sha256: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
       }}
    else
      {:error, reason} -> {:error, {:asset_write_failed, reason}}
    end
  end

  def local_path(stored_name) when is_binary(stored_name) do
    basename = Path.basename(stored_name)

    if basename == stored_name and basename != "" do
      path = Path.join(root_dir!(), basename)

      if File.regular?(path), do: {:ok, path}, else: {:error, :not_found}
    else
      {:error, :not_found}
    end
  end

  def root_dir! do
    :autolaunch
    |> Application.fetch_env!(:prelaunch_uploads)
    |> Keyword.fetch!(:root_dir)
    |> Path.expand()
  end

  def writable? do
    root_dir = root_dir!()

    with :ok <- File.mkdir_p(root_dir),
         test_path <- Path.join(root_dir, ".autolaunch-upload-check"),
         :ok <- File.write(test_path, "ok"),
         :ok <- File.rm(test_path) do
      true
    else
      _ -> false
    end
  end

  defp extension_for(media_type, file_name) do
    case {media_type, Path.extname(file_name)} do
      {"image/png", _} -> ".png"
      {"image/jpeg", _} -> ".jpg"
      {"image/webp", _} -> ".webp"
      {"image/gif", _} -> ".gif"
      {_, ext} when ext in [".png", ".jpg", ".jpeg", ".webp", ".gif"] -> ext
      _ -> ".bin"
    end
  end
end
