defmodule AutolaunchWeb.PrelaunchAssetControllerTest do
  use AutolaunchWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:autolaunch, :prelaunch_uploads)

    root_dir =
      Path.join(System.tmp_dir!(), "autolaunch-asset-route-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root_dir)
    File.write!(Path.join(root_dir, "asset_route.png"), "png-bytes")
    Application.put_env(:autolaunch, :prelaunch_uploads, root_dir: root_dir)

    on_exit(fn ->
      if previous do
        Application.put_env(:autolaunch, :prelaunch_uploads, previous)
      else
        Application.delete_env(:autolaunch, :prelaunch_uploads)
      end

      File.rm_rf(root_dir)
    end)

    :ok
  end

  test "serves uploaded prelaunch assets from writable storage", %{conn: conn} do
    conn = get(conn, "/prelaunch-assets/asset_route.png")

    assert response(conn, 200) == "png-bytes"
    assert get_resp_header(conn, "content-type") == ["image/png; charset=utf-8"]
  end

  test "rejects path traversal", %{conn: conn} do
    conn = get(conn, "/prelaunch-assets/..%2Fsecret.png")

    assert response(conn, 404) == "Not found"
  end
end
