defmodule Mix.Tasks.Autolaunch.VerifyDeployTest do
  use Autolaunch.DataCase, async: false

  import ExUnit.CaptureIO

  alias Autolaunch.ReleaseDeployVerifierTestSupport, as: Support

  setup do
    previous_launch = Application.get_env(:autolaunch, :launch, [])
    previous_rpc = Application.get_env(:autolaunch, :cca_rpc_adapter)
    previous_mode = Application.get_env(:autolaunch, :release_deploy_verifier_rpc_mode)

    Application.put_env(:autolaunch, :launch, Support.launch_config(previous_launch))
    Application.put_env(:autolaunch, :cca_rpc_adapter, Support.Rpc)
    Support.set_rpc_mode(:healthy)

    on_exit(fn ->
      Application.put_env(:autolaunch, :launch, previous_launch)

      if previous_rpc do
        Application.put_env(:autolaunch, :cca_rpc_adapter, previous_rpc)
      else
        Application.delete_env(:autolaunch, :cca_rpc_adapter)
      end

      if previous_mode do
        Application.put_env(:autolaunch, :release_deploy_verifier_rpc_mode, previous_mode)
      else
        Application.delete_env(:autolaunch, :release_deploy_verifier_rpc_mode)
      end
    end)

    Support.insert_ready_job!()
    Mix.Task.reenable("autolaunch.verify_deploy")
    :ok
  end

  test "verify deploy task prints the success footer" do
    output =
      capture_io(fn ->
        Mix.Tasks.Autolaunch.VerifyDeploy.run(["--job", Support.job_id()])
      end)

    assert output =~ "Controller: #{Support.address(:controller)}"
    assert output =~ "Autolaunch deploy verification passed."
  end
end
