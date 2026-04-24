defmodule Autolaunch.BaseFamily do
  @moduledoc false

  @base_mainnet_chain_id 8_453
  @base_sepolia_chain_id 84_532

  @base_mainnet_usdc "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
  @base_sepolia_usdc "0x036cbd53842c5426634e7929541ec2318f3dcf7e"

  def base_mainnet_chain_id, do: @base_mainnet_chain_id
  def base_sepolia_chain_id, do: @base_sepolia_chain_id

  def canonical_usdc_address(@base_mainnet_chain_id), do: {:ok, @base_mainnet_usdc}
  def canonical_usdc_address(@base_sepolia_chain_id), do: {:ok, @base_sepolia_usdc}
  def canonical_usdc_address(_chain_id), do: {:error, :unsupported_base_family_chain}

  def canonical_usdc_address!(chain_id) do
    case canonical_usdc_address(chain_id) do
      {:ok, address} -> address
      {:error, reason} -> raise ArgumentError, "unsupported Base-family chain: #{inspect(reason)}"
    end
  end
end
