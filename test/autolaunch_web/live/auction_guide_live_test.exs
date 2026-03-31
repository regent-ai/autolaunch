defmodule AutolaunchWeb.AuctionGuideLiveTest do
  use AutolaunchWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "guide page renders the auction timeline and summary", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Guide strip"
    assert html =~ "How autolaunch auctions work."
    assert html =~ "Each auction sells 10% of an agent&#39;s revenue token supply."
    assert html =~ "USDC on Ethereum Sepolia"
    assert html =~ "Stake required"
    assert html =~ "The auction in order"
    assert html =~ "Claim first, stake second, earn third."
  end

  test "alias route serves the same guide", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/how-auctions-work")

    assert html =~ "How autolaunch auctions work."
    assert html =~ "All auctions are denominated in USDC on Ethereum Sepolia."
  end

  test "guide back returns to the overview step", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> element("#auction-guide-surface-scene")
      |> render_hook("regent:node_select", %{
        "target_id" => "guide:step:2",
        "face_id" => "guide",
        "meta" => %{"stepIndex" => 2}
      })

    assert html =~ "Back to overview"

    html =
      view
      |> element("button[phx-click='scene-back']")
      |> render_click()

    refute html =~ "Back to overview"
    assert html =~ "Current 1"
  end
end
