defmodule AutolaunchWeb.AuctionGuideLiveTest do
  use AutolaunchWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Autolaunch.Accounts
  alias Autolaunch.Xmtp

  @agent_private_key "0x1111111111111111111111111111111111111111111111111111111111111111"

  setup do
    previous_config = Application.get_env(:autolaunch, Xmtp, [])

    Application.put_env(
      :autolaunch,
      Xmtp,
      Keyword.merge(previous_config, agent_private_key: @agent_private_key)
    )

    :ok = Xmtp.reset_for_test!()
    assert {:ok, _room} = Xmtp.bootstrap_room!()

    on_exit(fn ->
      Application.put_env(:autolaunch, Xmtp, previous_config)
      :ok = Xmtp.reset_for_test!()
    end)

    :ok
  end

  test "guide page renders the auction timeline and summary", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Guide strip"
    assert html =~ "Pick the job you came here for, then go straight to it."
    assert html =~ "Back an active auction with USDC."
    assert html =~ "Launch through the CLI, then return here for the live market."
    assert html =~ "Join the live Autolaunch wire with your Privy wallet."

    assert html =~
             "Connect your Privy wallet to watch from the site and request a private-room seat."

    assert html =~ "The sale in plain English"
    assert html =~ "The live token split"
    assert html =~ "10 billion of the 100 billion token supply are sold in the auction."
    assert html =~ "Less timing game, more honest price discovery."
  end

  test "alias route serves the same guide", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/how-auctions-work")

    assert html =~ "Pick the job you came here for, then go straight to it."
    assert html =~ "Everyone who clears the same block gets the same clearing price"
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

  test "guide page can drive the XMTP join and send flow from the live view", %{conn: conn} do
    {:ok, human} =
      Accounts.upsert_human_by_privy_id("did:privy:guide-xmtp", %{
        "wallet_address" => "0x3333333333333333333333333333333333333333",
        "wallet_addresses" => ["0x3333333333333333333333333333333333333333"],
        "display_name" => "Guide Operator"
      })

    conn = init_test_session(conn, privy_user_id: human.privy_user_id)
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> element("#auction-guide-xmtp-room")
      |> render_hook("xmtp_join", %{})

    assert html =~ "Sign the XMTP identity message to join the private room."

    [_, request_id] =
      Regex.run(~r/data-pending-request-id="([^"]+)"/, html) ||
        flunk("expected a pending XMTP signature request in the rendered guide")

    html =
      view
      |> element("#auction-guide-xmtp-room")
      |> render_hook("xmtp_join_signature_signed", %{
        "request_id" => request_id,
        "signature" => "0xsigned"
      })

    assert html =~ "You are inside the private XMTP room."

    html =
      view
      |> element("#auction-guide-xmtp-room")
      |> render_hook("xmtp_send", %{"body" => "Hello from the guide"})

    assert html =~ "Hello from the guide"
    assert html =~ "joined"
  end
end
