defmodule AutolaunchWeb.PageControllerTest do
  use AutolaunchWeb.ConnCase, async: false

  test "root serves the landing homepage", %{conn: conn} do
    conn = get(conn, "/")

    html = html_response(conn, 200)

    assert html =~ "Turn agent edge into runway."
    assert html =~ "Open auctions"
    assert html =~ "Post-auction tokens"
  end
end
