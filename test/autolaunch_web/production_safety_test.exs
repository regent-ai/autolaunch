defmodule AutolaunchWeb.ProductionSafetyTest do
  use AutolaunchWeb.ConnCase, async: false

  test "production session cookies are marked secure" do
    assert AutolaunchWeb.Endpoint.session_options(:prod)[:secure] == true
  end

  test "dev dashboard is not routed in test and production builds", %{conn: conn} do
    conn = get(conn, "/dev/dashboard")

    assert response(conn, 404)
  end

  test "health check stays shallow", %{conn: conn} do
    conn = get(conn, "/health")

    assert json_response(conn, 200) == %{"ok" => true, "service" => "autolaunch"}
  end
end
