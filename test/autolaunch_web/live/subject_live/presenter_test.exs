defmodule AutolaunchWeb.SubjectLive.PresenterTest do
  use ExUnit.Case, async: true

  alias AutolaunchWeb.SubjectLive.Presenter

  test "builds routing snapshot display data" do
    snapshot =
      Presenter.routing_snapshot(%{
        eligible_revenue_share_percent: "80",
        pending_eligible_revenue_share_percent: "60",
        pending_eligible_revenue_share_bps: 6_000,
        eligible_revenue_share_bps: 8_000,
        verified_ingress_usdc: "90",
        launch_fee_usdc: "20",
        total_usdc_received: "125",
        share_change_history: [%{}]
      })

    assert snapshot.live_share == "80%"
    assert snapshot.pending_share == "60%"
    assert snapshot.verified_revenue == "110 USDC"
    assert snapshot.total_received == "125 USDC"
    assert snapshot.history_count == "1 recorded change"
    assert snapshot.change_chart.headline == "This share is scheduled to move from 80% to 60%."
  end

  test "builds empty routing state when subject is unavailable" do
    snapshot = Presenter.routing_snapshot(nil)

    assert snapshot.live_share == "100%"
    assert snapshot.pending_share == "No pending change"
    assert snapshot.change_chart == nil
  end

  test "translates share history entries" do
    entry = %{
      type: "activated",
      previous_share_percent: "80",
      new_share_percent: "60",
      cooldown_end: "2026-05-22T14:30:00Z",
      happened_at: "2026-05-01T14:30:00Z"
    }

    assert Presenter.history_label(entry) == "Live"
    assert Presenter.history_primary_value(entry) == "60%"
    assert Presenter.history_copy(entry) =~ "from 80% to 60%"
    assert Presenter.history_timestamp(entry) == "May 1, 2026 at 2:30 PM UTC"
  end

  test "translates subject action errors" do
    assert Presenter.action_error(:amount_required) ==
             "Enter an amount before preparing the wallet transaction."

    assert Presenter.action_error(:unknown) ==
             "Unable to prepare the wallet transaction right now."
  end
end
