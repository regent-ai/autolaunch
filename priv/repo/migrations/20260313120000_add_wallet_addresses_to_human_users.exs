defmodule Autolaunch.Repo.Migrations.AddWalletAddressesToHumanUsers do
  use Ecto.Migration

  def change do
    alter table(:autolaunch_human_users) do
      add :wallet_addresses, {:array, :string}, null: false, default: []
    end
  end
end
