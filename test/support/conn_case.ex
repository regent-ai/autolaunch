defmodule AutolaunchWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint AutolaunchWeb.Endpoint

      use Phoenix.VerifiedRoutes,
        endpoint: AutolaunchWeb.Endpoint,
        router: AutolaunchWeb.Router,
        statics: AutolaunchWeb.static_paths()

      import Plug.Conn
      import Phoenix.ConnTest
      import AutolaunchWeb.ConnCase
    end
  end

  setup tags do
    Autolaunch.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
