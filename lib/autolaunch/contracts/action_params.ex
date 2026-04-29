defmodule Autolaunch.Contracts.ActionParams do
  @moduledoc false

  alias Autolaunch.Evm

  @zero_address "0x0000000000000000000000000000000000000000"

  def prepare_tx(chain_id, to, data, resource, action, params \\ %{}, opts \\ []) do
    if blank?(to) or blank?(data) do
      {:error, :unsupported_action}
    else
      value = Keyword.get(opts, :value, "0x0")
      action_id = action_id(chain_id, to, value, data, resource, action)

      {:ok,
       %{
         action_id: action_id,
         resource: resource,
         action: action,
         chain_id: chain_id,
         target: to,
         calldata: data,
         expected_signer: Keyword.get(opts, :expected_signer),
         expires_at:
           DateTime.utc_now()
           |> DateTime.add(600, :second)
           |> DateTime.truncate(:second)
           |> DateTime.to_iso8601(),
         idempotency_key: action_id,
         risk_copy: risk_copy(resource, action),
         tx_request: %{chain_id: chain_id, to: to, value: value, data: data},
         params: params,
         submission_mode: "prepare_only"
       }}
    end
  end

  def prepare_tx_request(
        %{chain_id: chain_id, to: to, value: value, data: data},
        resource,
        action,
        params,
        opts
      ) do
    prepare_tx(chain_id, to, data, resource, action, params, Keyword.put(opts, :value, value))
  end

  def prepare_tx_request(
        %{chain_id: chain_id, to: to, value_hex: value, data: data},
        resource,
        action,
        params,
        opts
      ) do
    prepare_tx(chain_id, to, data, resource, action, params, Keyword.put(opts, :value, value))
  end

  def address_param(attrs, key) do
    Evm.normalize_required_address(Map.get(attrs, key))
  end

  def string_param(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if byte_size(trimmed) > 0 do
          {:ok, trimmed}
        else
          {:error, :invalid_string}
        end

      _ ->
        {:error, :invalid_string}
    end
  end

  def uint_param(attrs, key) do
    value = Map.get(attrs, key)

    cond do
      is_integer(value) and value >= 0 ->
        {:ok, value}

      is_binary(value) and value != "" ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed >= 0 -> {:ok, parsed}
          _ -> {:error, :invalid_uint}
        end

      true ->
        {:error, :invalid_uint}
    end
  end

  def boolean_param(attrs, key) do
    value = Map.get(attrs, key)

    case value do
      true -> {:ok, true}
      false -> {:ok, false}
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      "1" -> {:ok, true}
      "0" -> {:ok, false}
      1 -> {:ok, true}
      0 -> {:ok, false}
      _ -> {:error, :invalid_boolean}
    end
  end

  def blank?(value), do: value in [nil, "", @zero_address]

  defp action_id(chain_id, to, value, data, resource, action) do
    [
      chain_id,
      resource,
      action,
      String.downcase(to),
      String.downcase(value),
      String.downcase(data)
    ]
    |> Enum.join(":")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 32)
  end

  defp risk_copy("revenue_splitter", "pull_treasury_share"),
    do: "Collects the subject treasury share from launch fees into the subject revenue split."

  defp risk_copy("fee_vault", "withdraw_regent_share"),
    do: "Collects the Regent share from launch fees for the Regent recipient."

  defp risk_copy("subject", "stake"),
    do: "Stakes this subject token from the connected wallet."

  defp risk_copy("subject", "unstake"),
    do: "Unstakes this subject token back to the connected wallet."

  defp risk_copy("subject", "claim_usdc"),
    do: "Claims available Base USDC for this subject token."

  defp risk_copy("subject", "claim_emissions"),
    do: "Claims available subject token rewards."

  defp risk_copy("subject", "claim_and_stake_emissions"),
    do: "Claims available subject token rewards and stakes them."

  defp risk_copy("subject", "sweep_ingress"),
    do: "Moves Base USDC from this subject intake address into the subject revenue split."

  defp risk_copy("regent_staking", "stake"),
    do: "Stakes Regent from the connected wallet."

  defp risk_copy("regent_staking", "unstake"),
    do: "Unstakes Regent back to the connected wallet."

  defp risk_copy("regent_staking", "claim_usdc"),
    do: "Claims available Base USDC from Regent staking."

  defp risk_copy("regent_staking", "claim_regent"),
    do: "Claims available Regent rewards."

  defp risk_copy("regent_staking", "claim_and_restake_regent"),
    do: "Claims available Regent rewards and restakes them."

  defp risk_copy("regent_staking", "deposit_usdc"),
    do: "Deposits Base USDC into the Regent staking rail."

  defp risk_copy("regent_staking", "withdraw_treasury"),
    do: "Withdraws available Regent staking treasury USDC to the selected recipient."

  defp risk_copy("auction", "submit_bid"),
    do: "Submits a Base USDC bid for this auction."

  defp risk_copy("auction", "exit_bid"),
    do: "Exits this auction bid and settles the available return."

  defp risk_copy("auction", "exit_partially_filled_bid"),
    do: "Exits this partially filled auction bid with the current checkpoint hints."

  defp risk_copy("auction", "claim_bid"),
    do: "Claims tokens purchased by this auction bid."

  defp risk_copy(_resource, _action),
    do: "Review the wallet transaction before signing."
end
