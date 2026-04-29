defmodule Autolaunch.PrelaunchAssetStorageTest do
  use ExUnit.Case, async: false

  alias Autolaunch.Prelaunch.AssetStorage

  setup do
    previous = Application.get_env(:autolaunch, :prelaunch_uploads)

    root_dir =
      Path.join(System.tmp_dir!(), "autolaunch-upload-test-#{System.unique_integer([:positive])}")

    Application.put_env(:autolaunch, :prelaunch_uploads, root_dir: root_dir)

    on_exit(fn ->
      if previous do
        Application.put_env(:autolaunch, :prelaunch_uploads, previous)
      else
        Application.delete_env(:autolaunch, :prelaunch_uploads)
      end

      File.rm_rf(root_dir)
    end)

    %{root_dir: root_dir}
  end

  test "persists uploaded assets outside the release static directory", %{root_dir: root_dir} do
    assert {:ok, stored} = AssetStorage.persist("avatar.png", "image/png", "image-bytes")

    assert String.starts_with?(stored.storage_path, root_dir)
    assert stored.public_url =~ ~r{^/prelaunch-assets/asset_.+\.png$}
    assert File.read!(stored.storage_path) == "image-bytes"
    refute String.contains?(stored.storage_path, "priv/static")
  end

  test "only serves files from the configured upload directory" do
    assert {:error, :not_found} = AssetStorage.local_path("../secret.png")
  end
end
