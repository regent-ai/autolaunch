defmodule AutolaunchWeb.PageControllerTest do
  use AutolaunchWeb.ConnCase, async: false

  test "root serves the public auction guide", %{conn: conn} do
    conn = get(conn, "/")

    html = html_response(conn, 200)

    assert html =~ "Pick the job you came here for, then go straight to it."
    assert html =~ "Back an active auction with USDC."
  end
end
