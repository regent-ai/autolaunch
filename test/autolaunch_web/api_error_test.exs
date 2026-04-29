defmodule AutolaunchWeb.ApiErrorTest do
  use AutolaunchWeb.ConnCase, async: true

  alias AutolaunchWeb.ApiError

  test "renders the product error envelope", %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.put_resp_header("x-request-id", "req_autolaunch_test")
      |> Map.put(:request_path, "/v1/app/test")
      |> ApiError.render(:unprocessable_entity, "invalid_launch", "Launch details are incomplete")

    assert %{
             "ok" => false,
             "error" => %{
               "code" => "invalid_launch",
               "product" => "autolaunch",
               "status" => 422,
               "path" => "/v1/app/test",
               "request_id" => "req_autolaunch_test",
               "message" => "Launch details are incomplete",
               "next_steps" => nil
             }
           } = json_response(conn, 422)
  end
end
