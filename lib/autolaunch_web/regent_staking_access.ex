defmodule AutolaunchWeb.RegentStakingAccess do
  @moduledoc false

  alias Autolaunch.Evm

  def authorized_operator?(human) when is_map(human) do
    allowed_wallets = configured_operator_wallets()
    linked_wallets = linked_wallets(human)

    allowed_wallets != [] and Enum.any?(linked_wallets, &(&1 in allowed_wallets))
  end

  def authorized_operator?(_human), do: false

  defp configured_operator_wallets do
    :autolaunch
    |> Application.get_env(:regent_staking, [])
    |> Keyword.get(:operator_wallets, [])
    |> Enum.map(&Evm.normalize_address/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp linked_wallets(human) do
    [Map.get(human, :wallet_address) | List.wrap(Map.get(human, :wallet_addresses))]
    |> Enum.map(&Evm.normalize_address/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
