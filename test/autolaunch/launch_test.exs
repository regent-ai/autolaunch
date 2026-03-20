defmodule Autolaunch.LaunchTest do
  use Autolaunch.DataCase, async: true

  alias Autolaunch.Launch

  test "repo-backed auctions fail closed when none exist" do
    assert Launch.list_auctions() == []
  end

  test "terminal statuses match launch job polling expectations" do
    assert Launch.terminal_status?("ready")
    assert Launch.terminal_status?("failed")
    refute Launch.terminal_status?("queued")
  end

  test "chain options expose ethereum mainnet and sepolia only" do
    assert Enum.map(Launch.chain_options(), & &1.id) == [1, 11_155_111]
  end
end
