defmodule AutolaunchWeb.ContractsLive.Presenter do
  @moduledoc false

  alias Autolaunch.Evm

  def default_forms do
    %{
      "fee_registry_hook" => %{"enabled" => "true"},
      "ingress_factory_create" => %{"make_default" => "false"},
      "registry_manager" => %{"enabled" => "true"},
      "splitter_paused" => %{"paused" => "false"},
      "splitter_share" => %{"share_bps" => "10000"},
      "admin_revenue_share" => %{"enabled" => "true"},
      "admin_revenue_ingress" => %{"enabled" => "true"}
    }
  end

  def form_value(forms, form_name, key, default \\ "") do
    forms
    |> Map.get(form_name, %{})
    |> Map.get(key, default)
  end

  def prepare_error(:invalid_address), do: "One of the addresses is invalid."
  def prepare_error(:invalid_uint), do: "Amounts must be provided in whole onchain units."
  def prepare_error(:invalid_string), do: "A text value is required."
  def prepare_error(:invalid_boolean), do: "Choose a valid true or false option."
  def prepare_error(:operator_required), do: "Use an authorized operator wallet."
  def prepare_error(:eligible_share_too_low), do: "Eligible share must be at least 10%."
  def prepare_error(:eligible_share_too_high), do: "Eligible share cannot exceed 100%."

  def prepare_error(:eligible_share_step_too_large),
    do: "Eligible share changes can only move by up to 20 percentage points at a time."

  def prepare_error(:ingress_not_found),
    do: "That ingress account does not belong to the current subject."

  def prepare_error(:subject_config_unavailable),
    do: "The current subject settings could not be loaded for this action."

  def prepare_error(:safe_rotation_noop),
    do: "The new Safe must be different from the current one."

  def prepare_error(:unsupported_action),
    do: "That contract action is not supported from this console."

  def prepare_error(_reason), do: "The contract payload could not be prepared."

  def wallet_switch_prompt(nil, _job_scope, _subject_scope), do: nil

  def wallet_switch_prompt(current_human, job_scope, subject_scope) do
    active_wallet = Evm.normalize_address(Map.get(current_human, :wallet_address))
    linked_wallets = linked_wallets(current_human)

    cond do
      target =
          linked_wallet_target(
            active_wallet,
            linked_wallets,
            get_in(job_scope, [:job, :owner_address])
          ) ->
        %{wallet_address: target}

      target =
          linked_wallet_target(
            active_wallet,
            linked_wallets,
            get_in(subject_scope, [:registry, :subject_config, :treasury_safe])
          ) ->
        %{wallet_address: target}

      true ->
        nil
    end
  end

  defp linked_wallet_target(active_wallet, linked_wallets, target_wallet) do
    normalized_target = Evm.normalize_address(target_wallet)

    if normalized_target && normalized_target != active_wallet &&
         normalized_target in linked_wallets,
       do: normalized_target,
       else: nil
  end

  defp linked_wallets(current_human) do
    [
      Map.get(current_human, :wallet_address)
      | List.wrap(Map.get(current_human, :wallet_addresses))
    ]
    |> Enum.map(&Evm.normalize_address/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
