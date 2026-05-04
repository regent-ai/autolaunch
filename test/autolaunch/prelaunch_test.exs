defmodule Autolaunch.PrelaunchTest do
  use Autolaunch.DataCase, async: false

  alias Autolaunch.Accounts.HumanUser
  alias Autolaunch.Prelaunch
  alias Autolaunch.Prelaunch.Plan

  setup do
    human =
      %HumanUser{}
      |> HumanUser.changeset(%{
        privy_user_id: "did:privy:prelaunch-test",
        wallet_address: "0x1111111111111111111111111111111111111111"
      })
      |> Repo.insert!()

    %Plan{}
    |> Plan.create_changeset(%{
      plan_id: "plan_metadata",
      privy_user_id: human.privy_user_id,
      state: "draft",
      agent_id: "84532:42",
      chain_id: 84_532,
      token_name: "Atlas Coin",
      token_symbol: "ATLAS",
      agent_safe_address: "0x1111111111111111111111111111111111111111",
      metadata_draft: %{}
    })
    |> Repo.insert!()

    %{human: human}
  end

  test "metadata updates require the canonical metadata wrapper", %{human: human} do
    assert {:error, :metadata_required} =
             Prelaunch.update_metadata("plan_metadata", %{"title" => "Flat title"}, human)

    assert Repo.get_by!(Plan, plan_id: "plan_metadata").metadata_draft == %{}
  end

  test "metadata updates save canonical metadata", %{human: human} do
    assert {:ok, %{plan: %{metadata_draft: %{"title" => "Atlas Launch"}}}} =
             Prelaunch.update_metadata(
               "plan_metadata",
               %{"metadata" => %{"title" => "Atlas Launch"}},
               human
             )
  end
end
