defmodule Autolaunch.Repo.Migrations.IndexHumanWalletLookups do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists index(:autolaunch_human_users, [:wallet_address],
                           name: :autolaunch_human_users_wallet_address_index,
                           concurrently: true
                         )

    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS autolaunch_human_users_wallet_addresses_gin_index
      ON autolaunch_human_users
      USING GIN (wallet_addresses)
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS autolaunch_human_users_wallet_addresses_gin_index
      """
    )
  end
end
