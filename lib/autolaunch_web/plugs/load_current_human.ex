defmodule AutolaunchWeb.Plugs.LoadCurrentHuman do
  @moduledoc false

  import Plug.Conn

  alias Autolaunch.Accounts
  alias Autolaunch.Accounts.HumanUser

  @pending_wallet_session_key :privy_pending_wallet_address
  @pending_wallets_session_key :privy_pending_wallet_addresses

  def init(opts), do: opts

  def call(conn, _opts) do
    privy_user_id = get_session(conn, :privy_user_id)

    current_human =
      privy_user_id
      |> Accounts.get_human_by_privy_id()
      |> with_pending_wallets(
        normalize_wallet_address(get_session(conn, @pending_wallet_session_key)),
        normalize_wallet_addresses(get_session(conn, @pending_wallets_session_key))
      )

    assign(conn, :current_human, current_human)
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

  defp normalize_wallet_address(value) when is_binary(value) do
    case String.trim(value) do
      <<"0x", rest::binary>> = trimmed when byte_size(rest) == 40 ->
        if String.match?(rest, ~r/\A[0-9a-fA-F]{40}\z/u), do: String.downcase(trimmed), else: nil

      _ ->
        nil
    end
  end

  defp normalize_wallet_address(_value), do: nil

  defp normalize_wallet_addresses(values) when is_list(values) do
    values
    |> Enum.map(&normalize_wallet_address/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_wallet_addresses(_values), do: []
end
