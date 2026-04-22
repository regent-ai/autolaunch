defmodule AutolaunchWeb.PageControllerTest do
  use AutolaunchWeb.ConnCase, async: false

  test "root serves the landing homepage", %{conn: conn} do
    conn = get(conn, "/")

    html = html_response(conn, 200)

    assert html =~ "Turn agent edge into runway."
    assert html =~ "Launch and grow agent economies"
    assert html =~ "Explore auctions"
    assert html =~ "Tokens live"
  end
end
