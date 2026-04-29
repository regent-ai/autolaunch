defmodule AutolaunchWeb.Api.RegentStakingControllerTest do
  use AutolaunchWeb.ConnCase, async: false

  alias Autolaunch.Accounts

  @agent_wallet "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  @agent_chain_id "84532"
  @agent_registry "0x2222222222222222222222222222222222222222"
  @agent_token_id "44"
  @receipt_secret "autolaunch-test-shared-secret"

  defmodule RegentStakingStub do
    def overview(_human) do
      {:ok,
       %{
         chain_id: 84_532,
         contract_address: "0x9999999999999999999999999999999999999999",
         treasury_residual_usdc: "150"
       }}
    end

    def account(address, _human) do
      {:ok, %{wallet_address: String.downcase(address), wallet_claimable_usdc: "12"}}
    end

    def stake(%{"amount" => "1.5"}, %{
          "wallet_address" => "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        }) do
      {:ok,
       %{
         prepared: prepared("stake", "0x7acb7757", "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
       }}
    end

    def stake(%{"amount" => "1.5"}, _human) do
      {:ok,
       %{
         prepared: prepared("stake", "0x7acb7757")
       }}
    end

    def stake(_params, _human), do: {:error, :amount_required}

    def unstake(_params, _human) do
      {:ok,
       %{
         prepared: prepared("unstake", "0x8381e182")
       }}
    end

    def claim_usdc(_params, _human) do
      {:ok,
       %{
         prepared: prepared("claim_usdc", "0x42852610")
       }}
    end

    def prepare_deposit_usdc(_params) do
      {:ok,
       %{
         prepared: %{
           action_id: "prepared_deposit_usdc",
           resource: "regent_staking",
           action: "deposit_usdc",
           chain_id: 84_532,
           target: "0x9999999999999999999999999999999999999999",
           calldata: "0x7dc6bb98",
           expected_signer: nil,
           expires_at: "2999-01-01T00:00:00Z",
           idempotency_key: "prepared_deposit_usdc",
           risk_copy: "Deposits Base USDC into the Regent staking rail.",
           tx_request: %{
             chain_id: 84_532,
             to: "0x9999999999999999999999999999999999999999",
             value: "0x0",
             data: "0x7dc6bb98"
           }
         }
       }}
    end

    def prepare_withdraw_treasury(_params) do
      {:ok,
       %{
         prepared: %{
           action_id: "prepared_withdraw_treasury",
           resource: "regent_staking",
           action: "withdraw_treasury",
           chain_id: 84_532,
           target: "0x9999999999999999999999999999999999999999",
           calldata: "0xe13b5822",
           expected_signer: nil,
           expires_at: "2999-01-01T00:00:00Z",
           idempotency_key: "prepared_withdraw_treasury",
           risk_copy:
             "Withdraws available Regent staking treasury USDC to the selected recipient.",
           tx_request: %{
             chain_id: 84_532,
             to: "0x9999999999999999999999999999999999999999",
             value: "0x0",
             data: "0xe13b5822"
           }
         }
       }}
    end

    defp prepared(action, data, expected_signer \\ "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") do
      %{
        action_id: "prepared_#{action}",
        resource: "regent_staking",
        action: action,
        chain_id: 84_532,
        target: "0x9999999999999999999999999999999999999999",
        calldata: data,
        expected_signer: expected_signer,
        expires_at: "2999-01-01T00:00:00Z",
        idempotency_key: "prepared_#{action}",
        risk_copy: "Review the wallet transaction before signing.",
        tx_request: %{
          chain_id: 84_532,
          to: "0x9999999999999999999999999999999999999999",
          value: "0x0",
          data: data
        }
      }
    end
  end

  setup_all do
    original_siwa_cfg = Application.get_env(:autolaunch, :siwa, [])
    port = available_port()

    start_supervised!(
      {Bandit, plug: Autolaunch.TestSupport.SiwaBrokerStub, ip: {127, 0, 0, 1}, port: port}
    )

    Application.put_env(:autolaunch, :siwa,
      internal_url: "http://127.0.0.1:#{port}",
      shared_secret: @receipt_secret,
      http_connect_timeout_ms: 2_000,
      http_receive_timeout_ms: 5_000
    )

    on_exit(fn -> Application.put_env(:autolaunch, :siwa, original_siwa_cfg) end)

    :ok
  end

  setup do
    original = Application.get_env(:autolaunch, :regent_staking_api, [])
    original_staking = Application.get_env(:autolaunch, :regent_staking, [])

    Application.put_env(:autolaunch, :regent_staking_api, context_module: RegentStakingStub)

    Application.put_env(
      :autolaunch,
      :regent_staking,
      Keyword.put(original_staking, :operator_wallets, [
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      ])
    )

    on_exit(fn ->
      Application.put_env(:autolaunch, :regent_staking_api, original)
      Application.put_env(:autolaunch, :regent_staking, original_staking)
    end)

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("did:privy:regent-staking-api", %{
        "wallet_address" => "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "wallet_addresses" => ["0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
        "display_name" => "Operator"
      })

    %{human: human}
  end

  test "show returns the regent staking overview", %{conn: conn} do
    conn = get(conn, "/v1/app/regent/staking")

    assert %{
             "ok" => true,
             "chain_id" => 84_532,
             "treasury_residual_usdc" => "150"
           } = json_response(conn, 200)
  end

  test "account returns account state", %{conn: conn} do
    conn = get(conn, "/v1/app/regent/staking/account/0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")

    assert %{
             "ok" => true,
             "wallet_address" => "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
             "wallet_claimable_usdc" => "12"
           } = json_response(conn, 200)
  end

  test "stake returns a prepared wallet action", %{conn: conn} do
    conn = post(conn, "/v1/app/regent/staking/stake", %{"amount" => "1.5"})

    assert %{
             "ok" => true,
             "prepared" => %{
               "expected_signer" => "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
               "idempotency_key" => "prepared_stake",
               "tx_request" => %{"chain_id" => 84_532, "data" => "0x7acb7757"}
             }
           } = json_response(conn, 200)
  end

  test "agent stake route uses the signed agent wallet without a browser session", %{conn: conn} do
    conn =
      conn
      |> with_agent_headers()
      |> post("/v1/agent/regent/staking/stake", %{"amount" => "1.5"})

    assert %{
             "ok" => true,
             "prepared" => %{
               "expected_signer" => @agent_wallet,
               "idempotency_key" => "prepared_stake",
               "tx_request" => %{"chain_id" => 84_532, "data" => "0x7acb7757"}
             }
           } = json_response(conn, 200)
  end

  test "deposit prepare requires a browser session", %{conn: conn} do
    conn =
      post(conn, "/v1/app/regent/staking/deposit-usdc/prepare", %{
        "amount" => "250.5",
        "source_tag" => "base_manual",
        "source_ref" => "2026-03"
      })

    assert %{"ok" => false, "error" => %{"code" => "auth_required"}} =
             json_response(conn, 401)
  end

  test "deposit prepare returns a multisig payload for a signed-in user", %{
    conn: conn,
    human: human
  } do
    conn = init_test_session(conn, privy_user_id: human.privy_user_id)

    conn =
      post(conn, "/v1/app/regent/staking/deposit-usdc/prepare", %{
        "amount" => "250.5",
        "source_tag" => "base_manual",
        "source_ref" => "2026-03"
      })

    assert %{
             "ok" => true,
             "prepared" => %{
               "action" => "deposit_usdc",
               "tx_request" => %{"data" => "0x7dc6bb98"}
             }
           } = json_response(conn, 200)
  end

  test "deposit prepare requires an allowed operator wallet", %{conn: conn} do
    {:ok, human} =
      Accounts.upsert_human_by_privy_id("did:privy:regent-staking-non-operator", %{
        "wallet_address" => "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "wallet_addresses" => ["0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
        "display_name" => "Reader"
      })

    conn = init_test_session(conn, privy_user_id: human.privy_user_id)

    conn =
      post(conn, "/v1/app/regent/staking/deposit-usdc/prepare", %{
        "amount" => "250.5",
        "source_tag" => "base_manual",
        "source_ref" => "2026-03"
      })

    assert %{"ok" => false, "error" => %{"code" => "operator_required"}} =
             json_response(conn, 403)
  end

  defp with_agent_headers(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-agent-wallet-address", @agent_wallet)
    |> put_req_header("x-agent-chain-id", @agent_chain_id)
    |> put_req_header("x-agent-registry-address", @agent_registry)
    |> put_req_header("x-agent-token-id", @agent_token_id)
    |> put_req_header("x-siwa-receipt", receipt_token("autolaunch"))
  end

  defp receipt_token(audience) do
    now_ms = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    payload =
      %{
        "typ" => "siwa_receipt",
        "jti" => Ecto.UUID.generate(),
        "sub" => @agent_wallet,
        "aud" => audience,
        "verified" => "onchain",
        "iat" => now_ms,
        "exp" => now_ms + 600_000,
        "chain_id" => String.to_integer(@agent_chain_id),
        "nonce" => "nonce-#{System.unique_integer([:positive])}",
        "key_id" => @agent_wallet,
        "registry_address" => @agent_registry,
        "token_id" => @agent_token_id
      }
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    signature =
      :crypto.mac(:hmac, :sha256, @receipt_secret, payload)
      |> Base.url_encode64(padding: false)

    "#{payload}.#{signature}"
  end

  defp available_port do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
