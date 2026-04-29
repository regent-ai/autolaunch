defmodule AutolaunchWeb.PrelaunchAssetController do
  use AutolaunchWeb, :controller

  alias Autolaunch.Prelaunch.AssetStorage

  def show(conn, %{"file" => file}) do
    case AssetStorage.local_path(file) do
      {:ok, path} ->
        conn
        |> put_resp_content_type(MIME.from_path(path))
        |> send_file(200, path)

      {:error, :not_found} ->
        send_resp(conn, 404, "Not found")
    end
  end
end
