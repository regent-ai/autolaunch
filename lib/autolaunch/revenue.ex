defmodule Autolaunch.Revenue do
  @moduledoc false

  alias Autolaunch.Revenue.{Actions, IngressAccounts, Subjects, WalletPositions}

  defdelegate get_subject(subject_id, current_human \\ nil), to: Subjects
  defdelegate subject_scope(subject_id, current_human \\ nil), to: Subjects
  defdelegate subject_state(subject_id, current_human \\ nil), to: Subjects

  defdelegate subject_portfolio_state(subject_id, wallet_addresses, current_human \\ nil),
    to: Subjects

  defdelegate prepare_existing_token_subject(attrs, current_actor), to: Subjects
  defdelegate confirm_existing_token_subject(attrs, current_actor), to: Subjects
  defdelegate prepare_deferred_autolaunch(attrs, current_actor), to: Subjects
  defdelegate confirm_deferred_autolaunch(attrs, current_actor), to: Subjects
  defdelegate subjects_by_token(token), to: Subjects
  defdelegate subject_staking(subject_id), to: Subjects
  defdelegate subject_protocol_fee_settlements(subject_id), to: Subjects
  defdelegate subject_regent_emissions(subject_id), to: Subjects

  defdelegate subject_wallet_position(subject_id, wallet_address), to: WalletPositions
  defdelegate subject_wallet_positions(subject_id, wallet_addresses), to: WalletPositions
  defdelegate subject_obligation_metrics(subject_id, staker_addresses), to: WalletPositions

  defdelegate get_ingress(subject_id, current_human \\ nil), to: IngressAccounts
  defdelegate ingress_state(subject_id, current_human \\ nil), to: IngressAccounts
  defdelegate accounting_tags(subject_id, attrs, current_human \\ nil), to: IngressAccounts

  defdelegate stake(subject_id, attrs, current_human), to: Actions
  defdelegate unstake(subject_id, attrs, current_human), to: Actions
  defdelegate claim_usdc(subject_id, attrs, current_human), to: Actions
  defdelegate sweep_ingress(subject_id, ingress_address, attrs, current_human), to: Actions
end
