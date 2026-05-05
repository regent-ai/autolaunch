defmodule Autolaunch.Revenue.RevenueSubject do
  @moduledoc false
  use Autolaunch.Schema

  @primary_key {:subject_id, :string, autogenerate: false}
  @subject_kinds ~w(cca_launch existing_token_revenue deferred_autolaunch)
  @splitter_kinds ~w(denominator_v2 live_stake_fee_pool)
  @team_shared_statuses ~w(unverified team_shared dao_shared official_site_linked)

  schema "autolaunch_revenue_subjects" do
    field :chain_id, :integer
    field :subject_kind, :string
    field :splitter_kind, :string
    field :token_address, :string
    field :splitter_address, :string
    field :ingress_address, :string
    field :treasury_address, :string
    field :factory_address, :string
    field :creator_address, :string
    field :permissionless, :boolean, default: false
    field :staker_pool_bps, :integer
    field :protocol_skim_bps_snapshot, :integer
    field :current_protocol_skim_bps, :integer
    field :protocol_fee_usdc_total_raw, :string
    field :regent_emission_total_raw, :string
    field :regent_buyback_total_raw, :string
    field :oracle_kind, :string
    field :regent_weth_pool_id, :string
    field :team_shared_status, :string, default: "unverified"
    field :vesting_wallet_address, :string
    field :created_tx_hash, :string
    field :created_block_number, :integer
    field :created_log_index, :integer

    timestamps()
  end

  def changeset(subject, attrs) do
    subject
    |> cast(attrs, [
      :subject_id,
      :chain_id,
      :subject_kind,
      :splitter_kind,
      :token_address,
      :splitter_address,
      :ingress_address,
      :treasury_address,
      :factory_address,
      :creator_address,
      :permissionless,
      :staker_pool_bps,
      :protocol_skim_bps_snapshot,
      :current_protocol_skim_bps,
      :protocol_fee_usdc_total_raw,
      :regent_emission_total_raw,
      :regent_buyback_total_raw,
      :oracle_kind,
      :regent_weth_pool_id,
      :team_shared_status,
      :vesting_wallet_address,
      :created_tx_hash,
      :created_block_number,
      :created_log_index
    ])
    |> validate_required([
      :subject_id,
      :chain_id,
      :subject_kind,
      :splitter_kind,
      :token_address,
      :splitter_address,
      :treasury_address,
      :permissionless,
      :team_shared_status
    ])
    |> validate_inclusion(:subject_kind, @subject_kinds)
    |> validate_inclusion(:splitter_kind, @splitter_kinds)
    |> validate_inclusion(:team_shared_status, @team_shared_statuses)
    |> validate_number(:staker_pool_bps,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10_000
    )
    |> validate_number(:protocol_skim_bps_snapshot,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10_000
    )
    |> validate_number(:current_protocol_skim_bps,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10_000
    )
    |> unique_constraint(:created_tx_hash,
      name: :autolaunch_revenue_subjects_creation_log_unique
    )
  end
end
