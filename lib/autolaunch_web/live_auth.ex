defmodule AutolaunchWeb.LiveAuth do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Autolaunch.Accounts
  alias Autolaunch.Accounts.HumanUser
  alias Autolaunch.Evm

  @pending_wallet_session_key "privy_pending_wallet_address"
  @pending_wallets_session_key "privy_pending_wallet_addresses"

  def on_mount(:current_human, _params, session, socket) do
    current_human =
      session
      |> Map.get("privy_user_id")
      |> Accounts.get_human_by_privy_id()
      |> with_pending_wallets(
        normalize_wallet_address(Map.get(session, @pending_wallet_session_key)),
        normalize_wallet_addresses(Map.get(session, @pending_wallets_session_key))
      )

    {:cont, assign(socket, :current_human, current_human)}
  end

  defp with_pending_wallets(nil, _pending_wallet, _pending_wallets), do: nil
  defp with_pending_wallets(%HumanUser{} = human, nil, _pending_wallets), do: human

  defp with_pending_wallets(%HumanUser{} = human, pending_wallet, pending_wallets) do
    pending_wallets =
      case pending_wallets do
        [] ->
          [pending_wallet]

        values ->
          if Enum.member?(values, pending_wallet), do: values, else: [pending_wallet | values]
      end

    %{human | wallet_address: pending_wallet, wallet_addresses: pending_wallets}
  end

  defp normalize_wallet_address(value), do: Evm.normalize_address(value)

  defp normalize_wallet_addresses(values) when is_list(values) do
    values
    |> Enum.map(&normalize_wallet_address/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_wallet_addresses(_values), do: []
end
