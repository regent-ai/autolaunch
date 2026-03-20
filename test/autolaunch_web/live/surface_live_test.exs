defmodule AutolaunchWeb.SurfaceLiveTest do
  use AutolaunchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "launch page renders agent-first copy", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/launch")

    assert html =~ "Choose an eligible agent"
    assert html =~ "ERC-8004"
    assert html =~ "Configure token"
  end

  test "auctions page renders market copy", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/auctions")

    assert html =~ "Auction Market"
    assert html =~ "No auctions match the current filter."
  end

  test "positions page renders sign-in guidance for guests", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/positions")

    assert html =~ "Sign in to inspect your bids."
  end
end
