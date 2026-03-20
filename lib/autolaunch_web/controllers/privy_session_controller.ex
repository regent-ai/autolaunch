defmodule AutolaunchWeb.PrivySessionController do
  use AutolaunchWeb, :controller

  alias Autolaunch.Accounts
  alias Autolaunch.Privy
  alias AutolaunchWeb.ApiError

  def create(conn, params) do
    with {:ok, token} <- fetch_bearer_token(conn),
         {:ok, %{privy_user_id: privy_user_id}} <- Privy.verify_token(token),
         {:ok, human} <- Accounts.upsert_human_by_privy_id(privy_user_id, session_attrs(params)) do
      conn
      |> put_session(:privy_user_id, privy_user_id)
      |> json(%{
        ok: true,
        human: %{
          id: human.id,
          privy_user_id: human.privy_user_id,
          wallet_address: human.wallet_address,
          wallet_addresses: human.wallet_addresses,
          display_name: human.display_name,
          role: human.role
        }
      })
    else
      _ ->
        ApiError.render(conn, :unauthorized, "privy_required", "Valid Privy JWT required")
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session(:privy_user_id)
    |> json(%{ok: true})
  end

  defp fetch_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        normalized = String.trim(token)
        if normalized == "", do: {:error, :invalid_authorization_header}, else: {:ok, normalized}

      _ ->
        {:error, :invalid_authorization_header}
    end
  end

  defp session_attrs(params) do
    %{}
    |> maybe_put("wallet_address", Map.get(params, "wallet_address"))
    |> maybe_put(
      "wallet_addresses",
      normalize_wallet_addresses(Map.get(params, "wallet_addresses"))
    )
    |> maybe_put("display_name", Map.get(params, "display_name"))
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, _key, ""), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp normalize_wallet_addresses(values) when is_list(values) do
    values
    |> Enum.map(fn
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> String.downcase(trimmed)
        end

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_wallet_addresses(_values), do: nil
end
