defmodule AutolaunchWeb.ContractsLive.PresenterTest do
  use ExUnit.Case, async: true

  alias AutolaunchWeb.ContractsLive.Presenter

  test "provides default form state for contract actions" do
    forms = Presenter.default_forms()

    assert Presenter.form_value(forms, "splitter_share", "share_bps") == "10000"
    assert Presenter.form_value(forms, "missing", "key", "fallback") == "fallback"
  end

  test "translates prepare errors into public copy" do
    assert Presenter.prepare_error(:invalid_address) == "One of the addresses is invalid."
    assert Presenter.prepare_error(:unsupported_action) =~ "not supported"
    assert Presenter.prepare_error(:unknown) == "The contract payload could not be prepared."
  end

  test "asks for a linked wallet when a contract action needs another wallet" do
    human = %{
      wallet_address: "0x1111111111111111111111111111111111111111",
      wallet_addresses: [
        "0x1111111111111111111111111111111111111111",
        "0x2222222222222222222222222222222222222222"
      ]
    }

    job_scope = %{job: %{owner_address: "0x2222222222222222222222222222222222222222"}}

    assert Presenter.wallet_switch_prompt(human, job_scope, nil) ==
             %{wallet_address: "0x2222222222222222222222222222222222222222"}
  end

  test "does not ask for a wallet switch when the wallet is already active" do
    human = %{
      wallet_address: "0x1111111111111111111111111111111111111111",
      wallet_addresses: ["0x1111111111111111111111111111111111111111"]
    }

    job_scope = %{job: %{owner_address: "0x1111111111111111111111111111111111111111"}}

    assert Presenter.wallet_switch_prompt(human, job_scope, nil) == nil
  end
end
