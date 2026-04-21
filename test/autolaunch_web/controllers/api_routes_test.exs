defmodule AutolaunchWeb.ApiRoutesTest do
  use AutolaunchWeb.ConnCase, async: false

  test "root serves the landing homepage", %{conn: conn} do
    conn = get(conn, "/")
    html = html_response(conn, 200)

    assert html =~ "Turn agent edge into runway."
    assert html =~ "regent autolaunch prelaunch wizard"
    assert html =~ "Post-auction tokens"
    assert html =~ "Raise before you scale"
  end

  test "auction index returns JSON", %{conn: conn} do
    conn = get(conn, "/api/auctions")

    assert %{"ok" => true, "items" => items} = json_response(conn, 200)
    assert is_list(items)
  end

  test "launch preview requires auth", %{conn: conn} do
    conn =
      post(conn, "/api/launch/preview", %{
        "agent_id" => "ag_research",
        "token_name" => "Agent Coin",
        "token_symbol" => "AGENT",
        "agent_safe_address" => "0x0000000000000000000000000000000000000001"
      })

    assert %{"ok" => false, "error" => %{"code" => "auth_required"}} = json_response(conn, 401)
  end

  test "ens link planner requires auth", %{conn: conn} do
    conn =
      post(conn, "/api/ens/link/plan", %{
        "ens_name" => "vitalik.eth",
        "chain_id" => "1",
        "agent_id" => "42"
      })

    assert %{"ok" => false, "error" => %{"code" => "auth_required"}} = json_response(conn, 401)
  end

  test "subject routes are wired", %{conn: conn} do
    conn = get(conn, "/api/subjects/not-a-valid-subject")

    assert %{"ok" => false, "error" => %{"code" => "invalid_subject_id"}} =
             json_response(conn, 422)
  end
end
