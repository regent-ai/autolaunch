defmodule AutolaunchWeb.Api.SubjectControllerTest do
  use AutolaunchWeb.ConnCase, async: false

  alias Autolaunch.Accounts
  alias Autolaunch.Launch.Job
  alias Autolaunch.Repo

  @subject_id "0x" <> String.duplicate("1a", 32)
  @splitter "0x9999999999999999999999999999999999999999"
  @token "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  @wallet "0x1111111111111111111111111111111111111111"
  @agent_registry "0x9999000000000000000000000000000000008004"
  @agent_token_id "42"
  @receipt_secret "autolaunch-test-receipt-secret"

  defmodule FakeRpc do
    @splitter "0x9999999999999999999999999999999999999999"
    @token "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    @ingress_factory "0x2222222222222222222222222222222222222222"
    @subject_registry "0x3333333333333333333333333333333333333333"
    @ingress "0x7777777777777777777777777777777777777777"
    @usdc "0x5555555555555555555555555555555555555555"

    def block_number(_chain_id, _opts), do: {:ok, 1}

    def eth_call(84_532, @splitter, data, _opts) do
      selector = String.slice(data, 0, 10)

      case selector do
        "0x817b1cd2" -> {:ok, encode_uint(250 * Integer.pow(10, 18))}
        "0x549b5d48" -> {:ok, encode_uint(10_000)}
        "0xb663660a" -> {:ok, encode_uint(0)}
        "0x8c37a52f" -> {:ok, encode_uint(0)}
        "0x5cc76060" -> {:ok, encode_uint(0)}
        "0xcf51bfdd" -> {:ok, encode_uint(125 * Integer.pow(10, 6))}
        "0x6a142340" -> {:ok, encode_uint(15 * Integer.pow(10, 6))}
        "0x35816a75" -> {:ok, encode_uint(90 * Integer.pow(10, 6))}
        "0xe8bb5751" -> {:ok, encode_uint(20 * Integer.pow(10, 6))}
        "0x1aa91287" -> {:ok, encode_uint(10 * Integer.pow(10, 6))}
        "0x08c23673" -> {:ok, encode_uint(90 * Integer.pow(10, 6))}
        "0xddffd82a" -> {:ok, encode_uint(25 * Integer.pow(10, 6))}
        "0x966ed108" -> {:ok, encode_uint(25 * Integer.pow(10, 6))}
        "0xe76bcce9" -> {:ok, encode_uint(12 * Integer.pow(10, 6))}
        "0x76459dd5" -> {:ok, encode_uint(10 * Integer.pow(10, 6))}
        "0x5f78d5f4" -> {:ok, encode_uint(1 * Integer.pow(10, 6))}
        "0x60217267" -> {:ok, encode_uint(12 * Integer.pow(10, 18))}
        "0xb026ee79" -> {:ok, encode_uint(5 * Integer.pow(10, 6))}
        "0x05e1fd68" -> {:ok, encode_uint(preview_claimable_stake_token(data))}
        "0xc5c5ae3a" -> {:ok, encode_uint(preview_funded_claimable_stake_token(data))}
        "0x05f15537" -> {:ok, encode_uint(3 * Integer.pow(10, 18))}
        "0xcfb3d0aa" -> {:ok, encode_uint(8 * Integer.pow(10, 18))}
        "0x66ffb8de" -> {:ok, encode_uint(6 * Integer.pow(10, 18))}
        "0x3e413bee" -> {:ok, encode_address(@usdc)}
        _ -> {:error, :unsupported_call}
      end
    end

    def eth_call(84_532, @token, "0x70a08231" <> _rest, _opts),
      do: {:ok, encode_uint(90 * Integer.pow(10, 18))}

    def eth_call(84_532, @usdc, "0x70a08231" <> _rest, _opts),
      do: {:ok, encode_uint(7 * Integer.pow(10, 6))}

    def eth_call(84_532, @ingress_factory, data, _opts) do
      selector = String.slice(data, 0, 10)

      case selector do
        "0xca23dd76" -> {:ok, encode_uint(1)}
        "0xb87d9995" -> {:ok, encode_address(@ingress)}
        "0xb396721d" -> {:ok, encode_address(@ingress)}
        _ -> {:error, :unsupported_call}
      end
    end

    def eth_call(84_532, @subject_registry, "0x41c2ab07" <> _rest, _opts),
      do: {:ok, encode_bool(true)}

    def eth_call(_chain_id, _to, _data, _opts), do: {:error, :unsupported_call}

    def tx_by_hash(_chain_id, tx_hash, _opts) do
      case Process.get(:fake_rpc_transaction) do
        %{transaction_hash: ^tx_hash} = tx -> {:ok, tx}
        _ -> {:ok, nil}
      end
    end

    def tx_receipt(_chain_id, _tx_hash, _opts), do: {:ok, Process.get(:fake_rpc_receipt)}

    def get_logs(_chain_id, %{"topics" => [topic | _]} = _filter, _opts) do
      {:ok, Process.get({:fake_rpc_logs, topic}, Process.get(:fake_rpc_logs, []))}
    end

    def get_logs(_chain_id, _filter, _opts), do: {:ok, Process.get(:fake_rpc_logs, [])}

    defp encode_uint(value) do
      value
      |> Integer.to_string(16)
      |> String.pad_leading(64, "0")
      |> then(&("0x" <> &1))
    end

    defp encode_address(address) do
      "0x" <> String.pad_leading(String.slice(address, 2..-1//1), 64, "0")
    end

    defp encode_bool(true), do: "0x" <> String.pad_leading("1", 64, "0")

    defp preview_claimable_stake_token(<<"0x05e1fd68", encoded::binary>>) do
      case String.slice(encoded, -40, 40) |> String.downcase() do
        "1111111111111111111111111111111111111111" -> 4 * Integer.pow(10, 18)
        "2222222222222222222222222222222222222222" -> 3 * Integer.pow(10, 18)
        _ -> 0
      end
    end

    defp preview_funded_claimable_stake_token(<<"0xc5c5ae3a", encoded::binary>>) do
      case String.slice(encoded, -40, 40) |> String.downcase() do
        "1111111111111111111111111111111111111111" -> 2 * Integer.pow(10, 18)
        "2222222222222222222222222222222222222222" -> 1 * Integer.pow(10, 18)
        _ -> 0
      end
    end
  end

  setup %{conn: conn} do
    previous_adapter = Application.get_env(:autolaunch, :cca_rpc_adapter)
    previous_launch = Application.get_env(:autolaunch, :launch, [])
    previous_siwa = Application.get_env(:autolaunch, :siwa, [])
    port = available_port()

    start_supervised!(
      {Bandit, plug: Autolaunch.TestSupport.SiwaBrokerStub, ip: {127, 0, 0, 1}, port: port}
    )

    Application.put_env(:autolaunch, :cca_rpc_adapter, FakeRpc)

    Application.put_env(:autolaunch, :siwa,
      internal_url: "http://127.0.0.1:#{port}",
      http_connect_timeout_ms: 2_000,
      http_receive_timeout_ms: 5_000
    )

    Application.put_env(
      :autolaunch,
      :launch,
      Keyword.put(
        previous_launch,
        :revenue_ingress_factory_address,
        "0x2222222222222222222222222222222222222222"
      )
    )

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:autolaunch, :cca_rpc_adapter, previous_adapter)
      else
        Application.delete_env(:autolaunch, :cca_rpc_adapter)
      end

      Application.put_env(:autolaunch, :launch, previous_launch)
      Application.put_env(:autolaunch, :siwa, previous_siwa)
    end)

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("did:privy:subject-controller", %{
        "wallet_address" => @wallet,
        "wallet_addresses" => [@wallet],
        "display_name" => "Operator"
      })

    now = DateTime.utc_now()
    nonce = "nonce-#{System.unique_integer([:positive])}"

    {:ok, job} =
      %Job{}
      |> Job.create_changeset(%{
        job_id: "job_subject_controller",
        owner_address: @wallet,
        agent_id: "84532:42",
        token_name: "Atlas Coin",
        token_symbol: "ATLAS",
        agent_safe_address: @wallet,
        network: "base-sepolia",
        chain_id: 84_532,
        status: "ready",
        step: "ready",
        total_supply: "1000",
        message: "signed",
        siwa_nonce: nonce,
        siwa_signature: "sig",
        issued_at: now
      })
      |> Repo.insert()

    job
    |> Job.update_changeset(%{
      token_address: @token,
      strategy_address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      subject_registry_address: "0x3333333333333333333333333333333333333333",
      revenue_share_splitter_address: @splitter,
      default_ingress_address: "0x7777777777777777777777777777777777777777",
      subject_id: @subject_id
    })
    |> Repo.update!()

    %{conn: init_test_session(conn, privy_user_id: human.privy_user_id), human: human}
  end

  test "show returns subject state", %{conn: conn} do
    conn = get(conn, "/v1/app/subjects/#{@subject_id}")

    assert %{
             "ok" => true,
             "subject" => %{
               "subject_id" => @subject_id,
               "eligible_revenue_share_bps" => 10_000,
               "pending_eligible_revenue_share_bps" => nil,
               "total_usdc_received_raw" => 125_000_000,
               "direct_deposit_usdc_raw" => 15_000_000,
               "verified_ingress_usdc_raw" => 90_000_000,
               "launch_fee_usdc_raw" => 20_000_000,
               "regent_skim_usdc_raw" => 10_000_000,
               "staker_eligible_inflow_usdc_raw" => 90_000_000,
               "treasury_reserved_inflow_usdc_raw" => 25_000_000,
               "treasury_reserved_usdc_raw" => 12_000_000,
               "recognized_revenue_proof" => %{
                 "source" => "onchain_splitter",
                 "chain_id" => 84_532,
                 "ingress" => "0x7777777777777777777777777777777777777777",
                 "revsplit" => @splitter,
                 "block_number" => 1,
                 "amount_raw" => 125_000_000,
                 "amount" => "125",
                 "recipient_lane" => "subject_revenue",
                 "status" => "fresh"
               },
               "share_change_history" => []
             }
           } = json_response(conn, 200)
  end

  test "show accepts uppercase subject ids", %{conn: conn} do
    upper_subject_id = "0x" <> String.upcase(String.slice(@subject_id, 2..-1//1))

    conn = get(conn, "/v1/app/subjects/#{upper_subject_id}")

    assert %{"ok" => true, "subject" => %{"subject_id" => @subject_id}} = json_response(conn, 200)
  end

  test "ingress returns subject ingress state", %{conn: conn} do
    conn = get(conn, "/v1/app/subjects/#{@subject_id}/ingress")

    assert %{
             "ok" => true,
             "subject_id" => @subject_id,
             "default_ingress_address" => "0x7777777777777777777777777777777777777777",
             "can_manage_ingress" => true,
             "accounts" => [
               %{
                 "address" => "0x7777777777777777777777777777777777777777",
                 "is_default" => true,
                 "usdc_balance" => "7",
                 "usdc_balance_raw" => 7_000_000
               }
             ]
           } = json_response(conn, 200)
  end

  test "agent accounting tags returns payment labels from ingress logs", %{conn: conn} do
    Process.put({:fake_rpc_logs, Autolaunch.Revenue.Abi.accounting_tag_recorded_topic0()}, [
      %{
        address: "0x7777777777777777777777777777777777777777",
        topics: [
          Autolaunch.Revenue.Abi.accounting_tag_recorded_topic0(),
          encode_topic_uint(0),
          encode_topic_address(@wallet)
        ],
        data: encode_log_words([12, 1_250_000, "0x" <> String.duplicate("ab", 32)]),
        block_number: 12,
        transaction_hash: "0x" <> String.duplicate("1", 64),
        log_index: 0
      },
      %{
        address: "0x7777777777777777777777777777777777777777",
        topics: [
          Autolaunch.Revenue.Abi.accounting_tag_recorded_topic0(),
          encode_topic_uint(1),
          encode_topic_address(@wallet)
        ],
        data: encode_log_words([13, 2_000_000, "0x" <> String.duplicate("cd", 32)]),
        block_number: 13,
        transaction_hash: "0x" <> String.duplicate("2", 64),
        log_index: 1
      }
    ])

    Process.put({:fake_rpc_logs, Autolaunch.Revenue.Abi.usdc_revenue_deposited_topic0()}, [
      %{
        address: @splitter,
        topics: [
          Autolaunch.Revenue.Abi.usdc_revenue_deposited_topic0(),
          Autolaunch.Revenue.Abi.direct_deposit_source_kind_topic(),
          encode_topic_address(@wallet),
          encode_topic_uint(0)
        ],
        data:
          encode_log_words([
            3_500_000,
            0,
            1_000,
            0,
            0,
            0,
            0,
            "0x" <> String.duplicate("ef", 32)
          ]),
        block_number: 14,
        transaction_hash: "0x" <> String.duplicate("3", 64),
        log_index: 2
      }
    ])

    conn =
      conn
      |> with_agent_headers()
      |> get("/v1/agent/subjects/#{@subject_id}/accounting-tags?from_block=12&limit=3")

    assert %{
             "ok" => true,
             "subject_id" => @subject_id,
             "chain_id" => 84_532,
             "from_block" => 12,
             "cursor" => 0,
             "limit" => 3,
             "next_cursor" => 3,
             "has_more" => false,
             "accounting_tags" => [
               %{
                 "source" => "ingress_deposit",
                 "ingress_address" => "0x7777777777777777777777777777777777777777",
                 "tag_index" => 0,
                 "block_number" => 12,
                 "depositor" => @wallet,
                 "amount_raw" => 1_250_000,
                 "amount" => "1.25",
                 "label" => "0x" <> _,
                 "transaction_hash" => "0x" <> _
               },
               %{
                 "source" => "ingress_deposit",
                 "ingress_address" => "0x7777777777777777777777777777777777777777",
                 "tag_index" => 1,
                 "block_number" => 13,
                 "amount_raw" => 2_000_000,
                 "amount" => "2"
               },
               %{
                 "source" => "direct_deposit",
                 "ingress_address" => nil,
                 "splitter_address" => @splitter,
                 "tag_index" => nil,
                 "block_number" => 14,
                 "depositor" => @wallet,
                 "amount_raw" => 3_500_000,
                 "amount" => "3.5"
               }
             ]
           } = json_response(conn, 200)
  end

  test "stake requires auth", %{conn: conn} do
    conn = delete_session(conn, :privy_user_id)
    conn = post(conn, "/v1/app/subjects/#{@subject_id}/stake", %{"amount" => "1.0"})

    assert %{
             "ok" => false,
             "error" => %{"code" => "auth_required", "message" => "Connect a wallet first"}
           } = json_response(conn, 401)
  end

  test "stake returns a prepared wallet action without broadcasting a live update", %{conn: conn} do
    AutolaunchWeb.LiveUpdates.subscribe([:subjects, :positions, :regent])

    conn = post(conn, "/v1/app/subjects/#{@subject_id}/stake", %{"amount" => "1.5"})

    assert %{
             "ok" => true,
             "prepared" => %{
               "expected_signer" => @wallet,
               "idempotency_key" => idempotency_key,
               "risk_copy" => risk_copy,
               "wallet_action" => %{
                 "chain_id" => 84_532,
                 "to" => @splitter,
                 "data" => data
               }
             }
           } = json_response(conn, 200)

    assert is_binary(idempotency_key)
    assert is_binary(risk_copy)
    assert String.starts_with?(data, "0x7acb7757")
    refute_receive {:autolaunch_live_update, :changed}, 50
  end

  test "stake with tx hash requires amount", %{conn: conn} do
    conn =
      post(conn, "/v1/app/subjects/#{@subject_id}/stake", %{
        "tx_hash" => "0x" <> String.duplicate("b", 64)
      })

    assert %{"ok" => false, "error" => %{"code" => "amount_required"}} = json_response(conn, 422)
  end

  test "stake selector mismatch returns transaction_data_mismatch", %{conn: conn} do
    tx_hash = "0x" <> String.duplicate("c", 64)

    Process.put(:fake_rpc_transaction, %{
      transaction_hash: tx_hash,
      from: @wallet,
      to: @splitter,
      input: Autolaunch.Revenue.Abi.encode_claim_usdc(@wallet),
      value: "0x0",
      block_number: nil
    })

    Process.put(:fake_rpc_receipt, nil)

    conn =
      post(conn, "/v1/app/subjects/#{@subject_id}/stake", %{
        "amount" => "1.5",
        "tx_hash" => tx_hash
      })

    assert %{"ok" => false, "error" => %{"code" => "transaction_data_mismatch"}} =
             json_response(conn, 422)
  end

  test "same tx hash on a different action is rejected", %{conn: conn} do
    tx_hash = "0x" <> String.duplicate("d", 64)

    Process.put(:fake_rpc_transaction, %{
      transaction_hash: tx_hash,
      from: @wallet,
      to: @splitter,
      input: Autolaunch.Revenue.Abi.encode_stake(1_500_000_000_000_000_000, @wallet),
      value: "0x0",
      block_number: nil
    })

    Process.put(:fake_rpc_receipt, nil)

    conn =
      post(conn, "/v1/app/subjects/#{@subject_id}/stake", %{
        "amount" => "1.5",
        "tx_hash" => tx_hash
      })

    assert %{"ok" => false, "error" => %{"code" => "transaction_pending"}} =
             json_response(conn, 202)

    conn = post(conn, "/v1/app/subjects/#{@subject_id}/claim-usdc", %{"tx_hash" => tx_hash})

    assert %{"ok" => false, "error" => %{"code" => "transaction_hash_reused"}} =
             json_response(conn, 409)
  end

  test "unstake accepts a confirmed tx hash", %{conn: conn} do
    tx_hash = "0x" <> String.duplicate("b", 64)

    Process.put(:fake_rpc_transaction, %{
      transaction_hash: tx_hash,
      from: @wallet,
      to: @splitter,
      input: Autolaunch.Revenue.Abi.encode_unstake(250_000_000_000_000_000, @wallet),
      value: "0x0",
      block_number: nil
    })

    Process.put(:fake_rpc_receipt, %{
      transaction_hash: tx_hash,
      status: 1,
      from: @wallet,
      to: @splitter,
      logs: []
    })

    conn =
      post(conn, "/v1/app/subjects/#{@subject_id}/unstake", %{
        "amount" => "0.25",
        "tx_hash" => tx_hash
      })

    assert %{"ok" => true, "subject" => %{"subject_id" => @subject_id}} = json_response(conn, 200)
  end

  test "claim-usdc accepts a confirmed tx hash", %{conn: conn} do
    tx_hash = "0x" <> String.duplicate("a", 64)

    Process.put(:fake_rpc_transaction, %{
      transaction_hash: tx_hash,
      from: @wallet,
      to: @splitter,
      input: Autolaunch.Revenue.Abi.encode_claim_usdc(@wallet),
      value: "0x0",
      block_number: nil
    })

    Process.put(:fake_rpc_receipt, %{
      transaction_hash: tx_hash,
      status: 1,
      from: @wallet,
      to: @splitter,
      logs: []
    })

    conn =
      post(conn, "/v1/app/subjects/#{@subject_id}/claim-usdc", %{
        "tx_hash" => tx_hash
      })

    assert %{"ok" => true, "subject" => %{"subject_id" => @subject_id}} = json_response(conn, 200)
  end

  test "sweep-ingress accepts a confirmed tx hash", %{conn: conn} do
    tx_hash = "0x" <> String.duplicate("c", 64)

    Process.put(:fake_rpc_transaction, %{
      transaction_hash: tx_hash,
      from: @wallet,
      to: "0x7777777777777777777777777777777777777777",
      input: Autolaunch.Revenue.Abi.encode_sweep_usdc(),
      value: "0x0",
      block_number: nil
    })

    Process.put(:fake_rpc_receipt, %{
      transaction_hash: tx_hash,
      status: 1,
      from: @wallet,
      to: "0x7777777777777777777777777777777777777777",
      logs: []
    })

    conn =
      post(
        conn,
        "/v1/app/subjects/#{@subject_id}/ingress/0x7777777777777777777777777777777777777777/sweep",
        %{
          "tx_hash" => tx_hash
        }
      )

    assert %{"ok" => true, "subject" => %{"subject_id" => @subject_id}} = json_response(conn, 200)
  end

  test "malformed tx hashes are rejected", %{conn: conn} do
    conn =
      post(conn, "/v1/app/subjects/#{@subject_id}/stake", %{
        "amount" => "1.0",
        "tx_hash" => "bad-hash"
      })

    assert %{"ok" => false, "error" => %{"code" => "invalid_transaction_hash"}} =
             json_response(conn, 422)
  end

  defp with_agent_headers(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-agent-wallet-address", @wallet)
    |> put_req_header("x-agent-chain-id", "84532")
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
        "sub" => @wallet,
        "aud" => audience,
        "verified" => "onchain",
        "iat" => now_ms,
        "exp" => now_ms + 600_000,
        "chain_id" => 84_532,
        "nonce" => "nonce-#{System.unique_integer([:positive])}",
        "key_id" => @wallet,
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

  defp encode_log_words(values) do
    "0x" <> Enum.map_join(values, "", &encode_word/1)
  end

  defp encode_topic_uint(value), do: "0x" <> encode_word(value)

  defp encode_topic_address("0x" <> address) do
    "0x" <> String.pad_leading(String.downcase(address), 64, "0")
  end

  defp encode_word(value) when is_integer(value) and value >= 0 do
    value
    |> Integer.to_string(16)
    |> String.pad_leading(64, "0")
  end

  defp encode_word("0x" <> hex) when byte_size(hex) == 64, do: String.downcase(hex)
end
