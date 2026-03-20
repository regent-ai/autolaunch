defmodule Autolaunch.Accounts do
  @moduledoc false

  alias Autolaunch.Accounts.HumanUser
  alias Autolaunch.Repo

  def get_human_by_privy_id(nil), do: nil

  def get_human_by_privy_id(privy_user_id) when is_binary(privy_user_id) do
    Repo.get_by(HumanUser, privy_user_id: privy_user_id)
  end

  def upsert_human_by_privy_id(privy_user_id, attrs) do
    now = DateTime.utc_now()
    normalized_attrs = Map.put(attrs, "privy_user_id", privy_user_id)

    Repo.insert(
      HumanUser.changeset(%HumanUser{}, normalized_attrs),
      conflict_target: :privy_user_id,
      on_conflict: [set: upsert_fields(normalized_attrs, now)],
      returning: true
    )
  end

  defp upsert_fields(attrs, now) do
    attrs
    |> Enum.reduce([updated_at: now], fn
      {"wallet_address", value}, acc -> [{:wallet_address, normalize_address(value)} | acc]
      {:wallet_address, value}, acc -> [{:wallet_address, normalize_address(value)} | acc]
      {"wallet_addresses", value}, acc -> [{:wallet_addresses, normalize_addresses(value)} | acc]
      {:wallet_addresses, value}, acc -> [{:wallet_addresses, normalize_addresses(value)} | acc]
      {"display_name", value}, acc -> [{:display_name, value} | acc]
      {:display_name, value}, acc -> [{:display_name, value} | acc]
      {"role", value}, acc -> [{:role, value} | acc]
      {:role, value}, acc -> [{:role, value} | acc]
      _, acc -> acc
    end)
    |> Enum.reverse()
  end

  defp normalize_address(value) when is_binary(value), do: String.downcase(String.trim(value))
  defp normalize_address(_value), do: nil

  defp normalize_addresses(values) when is_list(values) do
    values
    |> Enum.map(&normalize_address/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_addresses(_values), do: []
end
