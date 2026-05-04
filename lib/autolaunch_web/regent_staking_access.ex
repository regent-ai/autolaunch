defmodule AutolaunchWeb.RegentStakingAccess do
  @moduledoc false

  alias Autolaunch.Evm

  def authorized_operator?(human) when is_map(human) do
    match?({:ok, _wallet_address}, authorized_operator_wallet(human))
  end

  def authorized_operator?(_human), do: false

  def authorized_operator_wallet(human) when is_map(human) do
    allowed_wallets = configured_operator_wallets()
    linked_wallets = linked_wallets(human)

    case Enum.find(linked_wallets, &(&1 in allowed_wallets)) do
      wallet_address when is_binary(wallet_address) -> {:ok, wallet_address}
      _ -> {:error, :operator_required}
    end
  end

  def authorized_operator_wallet(_human), do: {:error, :operator_required}

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
