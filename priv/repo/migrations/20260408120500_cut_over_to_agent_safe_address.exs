defmodule Autolaunch.Repo.Migrations.CutOverToAgentSafeAddress do
  use Ecto.Migration

  def change do
    rename table(:autolaunch_jobs), :recovery_safe_address, to: :agent_safe_address

    alter table(:autolaunch_jobs) do
      remove :auction_proceeds_recipient
      remove :ethereum_revenue_treasury
    end

    rename table(:autolaunch_prelaunch_plans), :treasury_safe_address, to: :agent_safe_address

    alter table(:autolaunch_prelaunch_plans) do
      remove :auction_proceeds_recipient
      remove :ethereum_revenue_treasury
    end
  end
end
