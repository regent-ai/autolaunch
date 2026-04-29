defmodule Autolaunch.Repo.Migrations.CutoverLaunchRecordsToBaseChain do
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM autolaunch_bids
        WHERE network NOT IN ('base-sepolia', 'base-mainnet')
           OR chain_id NOT IN (84532, 8453)
      ) OR EXISTS (
        SELECT 1 FROM autolaunch_auctions
        WHERE network NOT IN ('base-sepolia', 'base-mainnet')
           OR chain_id NOT IN (84532, 8453)
      ) OR EXISTS (
        SELECT 1 FROM autolaunch_jobs
        WHERE network NOT IN ('base-sepolia', 'base-mainnet')
           OR chain_id NOT IN (84532, 8453)
      ) THEN
        RAISE EXCEPTION 'Autolaunch launch records include non-Base rows; stop and archive or migrate them before applying the Base-only launch constraints.';
      END IF;
    END $$;
    """)

    execute("""
    ALTER TABLE autolaunch_jobs
      ALTER COLUMN network SET DEFAULT 'base-sepolia',
      ALTER COLUMN chain_id SET DEFAULT 84532
    """)

    execute("""
    ALTER TABLE autolaunch_auctions
      ALTER COLUMN network SET DEFAULT 'base-sepolia',
      ALTER COLUMN chain_id SET DEFAULT 84532
    """)

    execute("""
    ALTER TABLE autolaunch_bids
      ALTER COLUMN network SET DEFAULT 'base-sepolia',
      ALTER COLUMN chain_id SET DEFAULT 84532
    """)

    execute("""
    ALTER TABLE autolaunch_jobs
      DROP CONSTRAINT IF EXISTS autolaunch_jobs_chain_id_ethereum_only,
      DROP CONSTRAINT IF EXISTS autolaunch_jobs_network_ethereum_only,
      DROP CONSTRAINT IF EXISTS autolaunch_jobs_chain_id_sepolia_only,
      DROP CONSTRAINT IF EXISTS autolaunch_jobs_network_sepolia_only,
      DROP CONSTRAINT IF EXISTS autolaunch_jobs_chain_id_base_only,
      DROP CONSTRAINT IF EXISTS autolaunch_jobs_network_base_only,
      DROP CONSTRAINT IF EXISTS autolaunch_jobs_chain_id_base_chain_only,
      DROP CONSTRAINT IF EXISTS autolaunch_jobs_network_base_chain_only
    """)

    execute("""
    ALTER TABLE autolaunch_auctions
      DROP CONSTRAINT IF EXISTS autolaunch_auctions_chain_id_ethereum_only,
      DROP CONSTRAINT IF EXISTS autolaunch_auctions_network_ethereum_only,
      DROP CONSTRAINT IF EXISTS autolaunch_auctions_chain_id_sepolia_only,
      DROP CONSTRAINT IF EXISTS autolaunch_auctions_network_sepolia_only,
      DROP CONSTRAINT IF EXISTS autolaunch_auctions_chain_id_base_only,
      DROP CONSTRAINT IF EXISTS autolaunch_auctions_network_base_only,
      DROP CONSTRAINT IF EXISTS autolaunch_auctions_chain_id_base_chain_only,
      DROP CONSTRAINT IF EXISTS autolaunch_auctions_network_base_chain_only
    """)

    execute("""
    ALTER TABLE autolaunch_bids
      DROP CONSTRAINT IF EXISTS autolaunch_bids_chain_id_ethereum_only,
      DROP CONSTRAINT IF EXISTS autolaunch_bids_network_ethereum_only,
      DROP CONSTRAINT IF EXISTS autolaunch_bids_chain_id_sepolia_only,
      DROP CONSTRAINT IF EXISTS autolaunch_bids_network_sepolia_only,
      DROP CONSTRAINT IF EXISTS autolaunch_bids_chain_id_base_only,
      DROP CONSTRAINT IF EXISTS autolaunch_bids_network_base_only,
      DROP CONSTRAINT IF EXISTS autolaunch_bids_chain_id_base_chain_only,
      DROP CONSTRAINT IF EXISTS autolaunch_bids_network_base_chain_only
    """)

    execute("""
    ALTER TABLE autolaunch_jobs
      ADD CONSTRAINT autolaunch_jobs_chain_id_base_chain_only CHECK (chain_id IN (84532, 8453)),
      ADD CONSTRAINT autolaunch_jobs_network_base_chain_only CHECK (network IN ('base-sepolia', 'base-mainnet'))
    """)

    execute("""
    ALTER TABLE autolaunch_auctions
      ADD CONSTRAINT autolaunch_auctions_chain_id_base_chain_only CHECK (chain_id IN (84532, 8453)),
      ADD CONSTRAINT autolaunch_auctions_network_base_chain_only CHECK (network IN ('base-sepolia', 'base-mainnet'))
    """)

    execute("""
    ALTER TABLE autolaunch_bids
      ADD CONSTRAINT autolaunch_bids_chain_id_base_chain_only CHECK (chain_id IN (84532, 8453)),
      ADD CONSTRAINT autolaunch_bids_network_base_chain_only CHECK (network IN ('base-sepolia', 'base-mainnet'))
    """)
  end

  def down do
    raise "irreversible migration"
  end
end
