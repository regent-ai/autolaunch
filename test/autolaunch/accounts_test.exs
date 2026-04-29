defmodule Autolaunch.AccountsTest do
  use Autolaunch.DataCase, async: true

  alias Autolaunch.Accounts

  @wallet "0x1111111111111111111111111111111111111111"

  test "upsert_human_by_privy_id normalizes blank wallet data on insert" do
    {:ok, human} =
      Accounts.upsert_human_by_privy_id("did:privy:accounts-upsert", %{
        "display_name" => "Blank Wallet",
        "wallet_address" => "   ",
        "wallet_addresses" => ["   ", @wallet, "  "],
        "xmtp_inbox_id" => "   "
      })

    assert human.wallet_address == nil
    assert human.wallet_addresses == [@wallet]
    assert human.xmtp_inbox_id == nil
    assert Accounts.get_human_by_wallet_address("   ") == nil
  end

  test "update_human normalizes blank wallet data on update" do
    {:ok, human} =
      Accounts.upsert_human_by_privy_id("did:privy:accounts-update", %{
        "display_name" => "Update Wallet",
        "wallet_address" => @wallet,
        "wallet_addresses" => [@wallet],
        "xmtp_inbox_id" => "inbox-123"
      })

    {:ok, updated_human} =
      Accounts.update_human(human, %{
        "wallet_address" => "   ",
        "wallet_addresses" => ["   "],
        "xmtp_inbox_id" => "   "
      })

    assert updated_human.wallet_address == nil
    assert updated_human.wallet_addresses == []
    assert updated_human.xmtp_inbox_id == nil
  end

  test "finds humans by indexed linked wallet address" do
    linked_wallet = "0x3333333333333333333333333333333333333333"

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("did:privy:accounts-linked-wallet", %{
        "display_name" => "Linked Wallet",
        "wallet_address" => "0x2222222222222222222222222222222222222222",
        "wallet_addresses" => [linked_wallet]
      })

    assert %Autolaunch.Accounts.HumanUser{id: id} =
             Accounts.get_human_by_wallet_address(String.upcase(linked_wallet))

    assert id == human.id
  end
end
