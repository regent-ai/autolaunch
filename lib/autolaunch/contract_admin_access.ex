defmodule Autolaunch.ContractAdminAccess do
  @moduledoc false

  alias Autolaunch.Evm

  def authorized_operator_wallet(actor) when is_map(actor) do
    allowed_wallets = configured_operator_wallets()
    linked_wallets = linked_wallets(actor)

    case Enum.find(linked_wallets, &(&1 in allowed_wallets)) do
      wallet_address when is_binary(wallet_address) -> {:ok, wallet_address}
      _ -> {:error, :operator_required}
    end
  end

  def authorized_operator_wallet(_actor), do: {:error, :operator_required}

  defp configured_operator_wallets do
    :autolaunch
    |> Application.get_env(:contract_admin, [])
    |> Keyword.get(:operator_wallets, [])
    |> normalize_wallets()
  end

  defp linked_wallets(actor) do
    [
      Map.get(actor, :wallet_address),
      Map.get(actor, "wallet_address")
      | List.wrap(Map.get(actor, :wallet_addresses)) ++
          List.wrap(Map.get(actor, "wallet_addresses"))
    ]
    |> normalize_wallets()
  end

  defp normalize_wallets(wallets) do
    wallets
    |> Enum.map(&Evm.normalize_address/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
