defmodule AutolaunchWeb.ClientIp do
  @moduledoc false

  def from_conn(%Plug.Conn{remote_ip: remote_ip}) when is_tuple(remote_ip) do
    remote_ip
    |> :inet.ntoa()
    |> to_string()
  end

  def from_conn(_conn), do: ""
end
