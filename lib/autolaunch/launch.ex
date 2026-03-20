defmodule Autolaunch.Launch do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Autolaunch.Accounts.HumanUser
  alias Autolaunch.CCA.Contract, as: CCAContract
  alias Autolaunch.CCA.Market, as: CCAMarket
  alias Autolaunch.CCA.QuoteEngine
  alias Autolaunch.ERC8004
  alias Autolaunch.Launch.Auction
  alias Autolaunch.Launch.Bid
  alias Autolaunch.Launch.External.TokenLaunch
  alias Autolaunch.Launch.Job
  alias Autolaunch.Repo
  alias Autolaunch.Siwa

  @terminal_statuses ~w(ready failed blocked)
  @eligibility_check_keys ~w(ownerOrOperatorAuthorized noPriorSuccessfulLaunch)
  @fee_split %{
    headline:
      "2% trade fee -> 1% launch treasury + 1% Regent multisig (0x9fa152B0EAdbFe9A7c5C0a8e1D11784f22669a3e).",
    trade_fee_bps: 200,
    treasury_bps: 100,
    regent_multisig_bps: 100,
    regent_multisig_address: "0x9fa152b0eadbfe9a7c5c0a8e1d11784f22669a3e"
  }
  @chain_configs %{
    1 => %{
      id: 1,
      key: "ethereum-mainnet",
      family: "ethereum",
      label: "Ethereum Mainnet",
      short_label: "Ethereum",
      uniswap_network: "ethereum",
      testnet?: false
    },
    11_155_111 => %{
      id: 11_155_111,
      key: "ethereum-sepolia",
      family: "ethereum",
      label: "Ethereum Sepolia",
      short_label: "Ethereum Sepolia",
      uniswap_network: nil,
      testnet?: true
    }
  }
  @supported_chain_ids [1, 11_155_111]

  def fee_split_summary, do: @fee_split

  def chain_options do
    @supported_chain_ids
    |> Enum.map(&chain_config!/1)
    |> Enum.map(fn config ->
      %{
        id: config.id,
        key: config.key,
        family: config.family,
        label: config.label,
        short_label: config.short_label,
        testnet?: config.testnet?
      }
    end)
  end

  def list_agents(nil), do: []

  def list_agents(%HumanUser{} = human) do
    wallet_addresses = linked_wallet_addresses(human)

    if wallet_addresses == [] do
      []
    else
      wallet_addresses
      |> ERC8004.list_accessible_identities(@supported_chain_ids)
      |> Enum.map(&agent_card_from_identity(&1, wallet_addresses))
    end
  rescue
    Req.TransportError -> []
    DBConnection.ConnectionError -> []
    Postgrex.Error -> []
    Ecto.QueryError -> []
  end

  def get_agent(%HumanUser{} = human, agent_id) when is_binary(agent_id) do
    Enum.find(list_agents(human), &(&1.agent_id == agent_id or &1.id == agent_id))
  end

  def get_agent(_human, _agent_id), do: nil

  def launch_readiness_for_agent(nil, _agent_id), do: nil

  def launch_readiness_for_agent(%HumanUser{} = human, agent_id) do
    if blank?(agent_id), do: nil, else: human |> get_agent(agent_id) |> agent_readiness()
  rescue
    Req.TransportError -> nil
    DBConnection.ConnectionError -> nil
    Postgrex.Error -> nil
    Ecto.QueryError -> nil
  end

  def preview_launch(attrs, %HumanUser{} = human) do
    with :ok <- ensure_authenticated_human(human),
         agent when is_map(agent) <- get_agent(human, Map.get(attrs, "agent_id")),
         :ok <- ensure_agent_eligible(agent),
         {:ok, token_name} <-
           required_text(Map.get(attrs, "token_name"), 80, :token_name_required),
         {:ok, token_symbol} <-
           required_text(Map.get(attrs, "token_symbol"), 16, :token_symbol_required),
         {:ok, treasury_address} <- required_address(Map.get(attrs, "treasury_address")),
         {:ok, chain} <- normalize_launch_chain(attrs),
         total_supply = normalize_total_supply(Map.get(attrs, "total_supply")),
         launch_notes = normalize_optional_text(Map.get(attrs, "launch_notes"), 1_000) do
      preview = %{
        agent: agent,
        token: %{
          name: token_name,
          symbol: token_symbol,
          chain: chain.key,
          chain_id: chain.id,
          chain_family: chain.family,
          chain_label: chain.label,
          treasury_address: treasury_address,
          total_supply: total_supply
        },
        economics: fee_split_summary(),
        launch_ready: true,
        launch_blockers: [],
        permanence_notes: [
          "One ERC-8004 identity can launch at most one Agent Coin.",
          "Treasury and fee split become part of the auction surface immediately after launch."
        ],
        next_steps: [
          "Sign the SIWA message with a linked wallet that controls this ERC-8004 identity.",
          "Queue deploy job.",
          "Wait for the auction page to go live."
        ],
        launch_notes: launch_notes
      }

      {:ok, preview}
    else
      nil -> {:error, :agent_not_found}
      {:error, _} = error -> error
      %{} = agent -> {:error, {:agent_not_eligible, agent}}
    end
  end

  def preview_launch(_attrs, _human), do: {:error, :unauthorized}

  def create_launch_job(attrs, %HumanUser{} = human, request_ip) do
    with :ok <- ensure_authenticated_human(human),
         {:ok, preview} <- preview_launch(attrs, human),
         {:ok, wallet_address} <- required_address(Map.get(attrs, "wallet_address")),
         {:ok, message} <- required_text(Map.get(attrs, "message"), 8_000, :message_required),
         {:ok, signature} <-
           required_text(Map.get(attrs, "signature"), 4_000, :signature_required),
         {:ok, nonce} <- required_text(Map.get(attrs, "nonce"), 255, :nonce_required),
         :ok <- ensure_wallet_matches_human(human, wallet_address),
         {:ok, chain_id} <- normalize_chain_id(Map.get(attrs, "chain_id")),
         :ok <- ensure_chain_id_matches_preview(chain_id, preview.token.chain_id),
         {:ok, _verification} <-
           Siwa.verify_wallet_signature(%{
             wallet_address: wallet_address,
             chain_id: chain_id,
             nonce: nonce,
             message: message,
             signature: signature
           }),
         issued_at = parse_issued_at(Map.get(attrs, "issued_at")),
         broadcast = truthy?(Map.get(attrs, "broadcast", true)),
         job_id = "job_" <> Ecto.UUID.generate() do
      agent = preview.agent

      job_attrs = %{
        job_id: job_id,
        privy_user_id: human.privy_user_id,
        owner_address: wallet_address,
        agent_id: agent.agent_id,
        agent_name: agent.name,
        token_name: preview.token.name,
        token_symbol: preview.token.symbol,
        treasury_address: preview.token.treasury_address,
        network: preview.token.chain,
        chain_id: chain_id,
        broadcast: broadcast,
        status: "queued",
        step: "queued",
        launch_notes: preview.launch_notes,
        total_supply: preview.token.total_supply,
        lifecycle_run_id: agent.lifecycle_run_id,
        vesting_beneficiary: preview.token.treasury_address,
        message: message,
        siwa_nonce: nonce,
        siwa_signature: signature,
        issued_at: issued_at,
        request_ip: request_ip,
        script_target: deploy_script_target(),
        deploy_workdir: deploy_workdir(),
        deploy_binary: deploy_binary(),
        rpc_host: deploy_rpc_host(chain_id)
      }

      {:ok, job} =
        %Job{}
        |> Job.create_changeset(job_attrs)
        |> Repo.insert()

      maybe_record_external_launch(job)
      queue_processing(job.job_id)

      {:ok, serialize_job(job)}
    else
      {:error, _} = error -> error
    end
  end

  def create_launch_job(_attrs, _human, _request_ip), do: {:error, :unauthorized}

  def get_job_response(job_id, owner_address \\ nil) do
    case Repo.get(Job, job_id) do
      nil ->
        nil

      %Job{} = job ->
        if owner_address && normalize_address(owner_address) != job.owner_address do
          {:error, :forbidden}
        else
          auction =
            if is_binary(job.auction_address) and job.auction_address != "" do
              get_auction_by_address(job.network, job.auction_address, nil)
            end

          %{job: serialize_job(job), auction: auction}
        end
    end
  rescue
    DBConnection.ConnectionError -> nil
    Postgrex.Error -> nil
  end

  def list_auctions(filters \\ %{}, current_human \\ nil) do
    Repo.all(
      from auction in Auction,
        order_by: [desc: auction.inserted_at]
    )
    |> Enum.map(&serialize_auction(&1, current_human))
    |> filter_auctions(filters)
    |> sort_auctions(filters)
  rescue
    DBConnection.ConnectionError -> []
    Postgrex.Error -> []
    Ecto.QueryError -> []
  end

  def get_auction(auction_id, current_human \\ nil) do
    Repo.one(
      from auction in Auction,
        where: fragment("coalesce(?, '')", auction.source_job_id) == ^auction_id,
        limit: 1
    )
    |> case do
      nil ->
        nil

      auction ->
        serialize_auction(auction, current_human)
    end
  rescue
    DBConnection.ConnectionError -> nil
    Postgrex.Error -> nil
    Ecto.QueryError -> nil
  end

  def quote_bid(auction_id, attrs, current_human \\ nil) do
    with auction when is_map(auction) <- get_auction(auction_id, current_human),
         {:ok, amount_decimal} <- required_decimal(Map.get(attrs, "amount"), :amount_required),
         {:ok, max_price_decimal} <-
           required_decimal(Map.get(attrs, "max_price"), :max_price_required),
         {:ok, amount_wei} <- decimal_to_wei(amount_decimal),
         {:ok, max_price_q96} <- decimal_price_to_q96(max_price_decimal),
         {:ok, raw_quote} <-
           QuoteEngine.quote(auction.chain_id, auction.auction_address, amount_wei, max_price_q96) do
      time_remaining_seconds = time_remaining_seconds(auction.ends_at)
      owner_address = current_human && primary_wallet_address(current_human)

      tx_request =
        if owner_address do
          case CCAMarket.build_submit_tx_request(
                 auction,
                 owner_address,
                 amount_wei,
                 max_price_q96
               ) do
            {:ok, request} -> serialize_tx_request(request)
            _ -> nil
          end
        end

      quote = %{
        auction_id: auction.id,
        amount: decimal_string(amount_decimal),
        max_price: decimal_string(max_price_decimal, 8),
        current_clearing_price: q96_price_to_string(raw_quote.current_clearing_price_q96),
        projected_clearing_price: q96_price_to_string(raw_quote.projected_clearing_price_q96),
        quote_mode: raw_quote.quote_mode,
        would_be_active_now: raw_quote.would_be_active_now,
        status_band: raw_quote.status_band,
        estimated_tokens_if_end_now:
          token_units_to_string(raw_quote.estimated_tokens_if_end_now_units),
        estimated_tokens_if_no_other_bids_change:
          token_units_to_string(raw_quote.estimated_tokens_if_no_other_bids_change_units),
        inactive_above_price: q96_price_to_string(raw_quote.inactive_above_price_q96),
        time_remaining_seconds: time_remaining_seconds,
        warnings: raw_quote.warnings,
        tx_request: tx_request
      }

      {:ok, quote}
    else
      nil -> {:error, :auction_not_found}
      {:error, _} = error -> error
    end
  end

  def place_bid(auction_id, attrs, %HumanUser{} = human) do
    with :ok <- ensure_authenticated_human(human),
         {:ok, wallet_address} <- required_address(human.wallet_address),
         {:ok, tx_hash} <- required_tx_hash(Map.get(attrs, "tx_hash")),
         {:ok, auction} <- fetch_auction_for_bid(auction_id, human),
         {:ok, amount_decimal} <- required_decimal(Map.get(attrs, "amount"), :amount_required),
         {:ok, max_price_decimal} <-
           required_decimal(Map.get(attrs, "max_price"), :max_price_required),
         {:ok, amount_wei} <- decimal_to_wei(amount_decimal),
         {:ok, max_price_q96} <- decimal_price_to_q96(max_price_decimal),
         {:ok, snapshot} <- CCAContract.snapshot(auction.chain_id, auction.auction_address),
         {:ok, registration} <-
           CCAMarket.register_submitted_bid(
             snapshot,
             tx_hash,
             wallet_address,
             amount_wei,
             max_price_q96
           ) do
      bid_id = local_bid_id(auction_id, registration.onchain_bid_id)
      quote_snapshot = build_bid_quote_snapshot(attrs, snapshot)
      now = DateTime.utc_now()

      bid_attrs = %{
        bid_id: bid_id,
        privy_user_id: human.privy_user_id,
        owner_address: wallet_address,
        auction_id: auction_id,
        auction_address: auction.auction_address,
        chain_id: auction.chain_id,
        agent_id: auction.agent_id,
        agent_name: auction.agent_name,
        network: auction.network,
        onchain_bid_id: Integer.to_string(registration.onchain_bid_id),
        submit_tx_hash: registration.submit_tx_hash,
        submit_block_number: registration.submit_block_number,
        amount: amount_decimal,
        max_price: max_price_decimal,
        current_clearing_price: q96_to_decimal(snapshot.checkpoint.clearing_price_q96),
        current_status: "active",
        estimated_tokens_if_end_now:
          decimal_from_string(Map.get(attrs, "estimated_tokens_if_end_now")),
        estimated_tokens_if_no_other_bids_change:
          decimal_from_string(Map.get(attrs, "estimated_tokens_if_no_other_bids_change")),
        inactive_above_price: decimal_from_string(Map.get(attrs, "inactive_above_price")),
        quote_snapshot: quote_snapshot,
        inserted_at: now,
        updated_at: now
      }

      {:ok, _bid} =
        Repo.insert(
          struct(Bid, bid_attrs),
          on_conflict: [
            set: [
              submit_tx_hash: registration.submit_tx_hash,
              submit_block_number: registration.submit_block_number,
              amount: amount_decimal,
              max_price: max_price_decimal,
              current_clearing_price: q96_to_decimal(snapshot.checkpoint.clearing_price_q96),
              current_status: "active",
              estimated_tokens_if_end_now:
                decimal_from_string(Map.get(attrs, "estimated_tokens_if_end_now")),
              estimated_tokens_if_no_other_bids_change:
                decimal_from_string(Map.get(attrs, "estimated_tokens_if_no_other_bids_change")),
              inactive_above_price: decimal_from_string(Map.get(attrs, "inactive_above_price")),
              quote_snapshot: quote_snapshot,
              updated_at: now
            ]
          ],
          conflict_target: [:auction_id, :onchain_bid_id]
        )

      with %Bid{} = tracked_bid <- Repo.get(Bid, bid_id) do
        {:ok, decorate_bid_position(tracked_bid, human)}
      else
        _ -> {:error, :bid_tracking_failed}
      end
    else
      {:error, :transaction_pending} -> {:error, :transaction_pending}
      {:error, :transaction_failed} -> {:error, :transaction_failed}
      {:error, _} = error -> error
    end
  end

  def place_bid(_auction_id, _attrs, _human), do: {:error, :unauthorized}

  def list_positions(human, filters \\ %{})

  def list_positions(nil, _filters), do: []

  def list_positions(%HumanUser{} = human, filters) do
    wallet_addresses = linked_wallet_addresses(human)

    bids =
      Repo.all(
        from bid in Bid,
          where: bid.owner_address in ^wallet_addresses,
          order_by: [desc: bid.inserted_at]
      )

    bids
    |> Enum.map(&decorate_bid_position(&1, human))
    |> filter_positions(filters)
  rescue
    DBConnection.ConnectionError -> []
    Postgrex.Error -> []
    Ecto.QueryError -> []
  end

  def exit_bid(bid_id, attrs, %HumanUser{} = human) do
    with :ok <- ensure_authenticated_human(human),
         {:ok, wallet_address} <- required_address(human.wallet_address),
         {:ok, tx_hash} <- required_tx_hash(Map.get(attrs, "tx_hash")),
         %Bid{} = bid <- Repo.get(Bid, bid_id),
         :ok <- ensure_bid_belongs_to_owner(bid, wallet_address),
         {:ok, auction} <- fetch_auction_for_bid(bid.auction_id, human),
         {:ok, snapshot} <- CCAContract.snapshot(auction.chain_id, auction.auction_address),
         {:ok, onchain_bid_id} <- parse_onchain_bid_id(bid.onchain_bid_id),
         {:ok, registration} <-
           CCAMarket.register_exit(snapshot, tx_hash, wallet_address, onchain_bid_id),
         {:ok, _updated_bid} <-
           bid
           |> Bid.update_changeset(%{
             current_status: "exited",
             exit_tx_hash: registration.exit_tx_hash,
             exited_at: DateTime.utc_now()
           })
           |> Repo.update() do
      {:ok, decorate_bid_position(Repo.get!(Bid, bid.bid_id), human)}
    else
      nil -> {:error, :not_found}
      {:error, :transaction_pending} -> {:error, :transaction_pending}
      {:error, :transaction_failed} -> {:error, :transaction_failed}
      {:error, _} = error -> error
    end
  end

  def exit_bid(_bid_id, _attrs, _human), do: {:error, :unauthorized}

  def claim_bid(bid_id, attrs, %HumanUser{} = human) do
    with :ok <- ensure_authenticated_human(human),
         {:ok, wallet_address} <- required_address(human.wallet_address),
         {:ok, tx_hash} <- required_tx_hash(Map.get(attrs, "tx_hash")),
         %Bid{} = bid <- Repo.get(Bid, bid_id),
         :ok <- ensure_bid_belongs_to_owner(bid, wallet_address),
         {:ok, auction} <- fetch_auction_for_bid(bid.auction_id, human),
         {:ok, snapshot} <- CCAContract.snapshot(auction.chain_id, auction.auction_address),
         {:ok, onchain_bid_id} <- parse_onchain_bid_id(bid.onchain_bid_id),
         {:ok, registration} <-
           CCAMarket.register_claim(snapshot, tx_hash, wallet_address, onchain_bid_id),
         {:ok, _updated_bid} <-
           bid
           |> Bid.update_changeset(%{
             current_status: "claimed",
             claim_tx_hash: registration.claim_tx_hash,
             claimed_at: DateTime.utc_now()
           })
           |> Repo.update() do
      {:ok, decorate_bid_position(Repo.get!(Bid, bid.bid_id), human)}
    else
      nil -> {:error, :not_found}
      {:error, :transaction_pending} -> {:error, :transaction_pending}
      {:error, :transaction_failed} -> {:error, :transaction_failed}
      {:error, _} = error -> error
    end
  end

  def claim_bid(_bid_id, _attrs, _human), do: {:error, :unauthorized}

  def queue_processing(job_id) do
    Task.Supervisor.start_child(Autolaunch.TaskSupervisor, fn -> process_job(job_id) end)
    :ok
  end

  def terminal_status?(status), do: status in @terminal_statuses

  def process_job(job_id) do
    case Repo.get(Job, job_id) do
      nil ->
        :ok

      %Job{} = job ->
        now = DateTime.utc_now()

        {:ok, job} =
          job
          |> Job.update_changeset(%{status: "running", step: "deploying", started_at: now})
          |> Repo.update()

        case run_launch(job) do
          {:ok, result} ->
            auction = persist_auction(job, result)

            {:ok, _updated_job} =
              job
              |> Job.update_changeset(%{
                status: "ready",
                step: "ready",
                finished_at: DateTime.utc_now(),
                auction_address: result.auction_address,
                token_address: result.token_address,
                hook_address: result.hook_address,
                fee_vault_address: result.fee_vault_address,
                official_pool_id: result.official_pool_id,
                tx_hash: result.tx_hash,
                uniswap_url: result.uniswap_url,
                stdout_tail: result.stdout_tail,
                stderr_tail: result.stderr_tail
              })
              |> Repo.update()

            mark_external_launch(job.job_id, "succeeded", %{
              auction_address: auction.auction_address,
              token_address: auction.token_address,
              metadata: %{
                "hook_address" => result.hook_address,
                "fee_vault_address" => result.fee_vault_address,
                "official_pool_id" => result.official_pool_id
              },
              launch_tx_hash: result.tx_hash,
              completed_at: DateTime.utc_now()
            })

          {:error, reason, logs} ->
            job
            |> Job.update_changeset(%{
              status: "failed",
              step: "failed",
              error_message: reason,
              finished_at: DateTime.utc_now(),
              stdout_tail: Map.get(logs, :stdout_tail, ""),
              stderr_tail: Map.get(logs, :stderr_tail, "")
            })
            |> Repo.update()

            mark_external_launch(job.job_id, "failed", %{completed_at: DateTime.utc_now()})
        end
    end
  rescue
    error ->
      case Repo.get(Job, job_id) do
        %Job{} = job ->
          _ =
            job
            |> Job.update_changeset(%{
              status: "failed",
              step: "failed",
              error_message: Exception.message(error),
              finished_at: DateTime.utc_now()
            })
            |> Repo.update()

        _ ->
          :ok
      end
  end

  defp agent_card_from_identity(identity, wallet_addresses) do
    existing_launch =
      Repo.one(
        from launch in TokenLaunch,
          where: launch.agent_id == ^identity.agent_id,
          order_by: [desc: launch.inserted_at],
          limit: 1
      )

    active_launch? =
      existing_launch && existing_launch.launch_status in ["queued", "running", "succeeded"]

    state =
      cond do
        active_launch? -> "already_launched"
        identity.access_mode in ["owner", "operator"] -> "eligible"
        true -> "wallet_bound"
      end

    readiness = agent_readiness(identity, existing_launch)
    blockers = launch_blockers(readiness)

    %{
      id: identity.agent_id,
      agent_id: identity.agent_id,
      name: identity.name,
      source: identity.source,
      supported_chains: chain_options(),
      state: state,
      access_mode: identity.access_mode,
      owner_address: identity.owner_address,
      operator_addresses: identity.operator_addresses,
      agent_wallet: identity.agent_wallet,
      image_url: identity.image_url,
      description: identity.description,
      ens: identity.ens,
      agent_uri: identity.agent_uri,
      web_endpoint: identity.web_endpoint,
      registry_address: identity.registry_address,
      token_id: identity.token_id,
      linked_wallet_addresses: wallet_addresses,
      blocker_texts: blockers,
      lifecycle_run_id: identity.agent_id,
      existing_token:
        if(existing_launch,
          do: %{
            status: existing_launch.launch_status,
            auction_id: existing_launch.launch_job_id,
            symbol: Map.get(existing_launch.metadata || %{}, "token_symbol"),
            token_address: existing_launch.token_address,
            auction_address: existing_launch.auction_address
          },
          else: nil
        )
    }
  end

  defp agent_readiness(nil), do: nil

  defp agent_readiness(agent) when is_map(agent) do
    agent_readiness(agent, agent[:existing_token])
  end

  defp agent_readiness(identity, existing_launch) do
    owner_or_operator? = identity.access_mode in ["owner", "operator"]
    existing_launch? = active_launch_record?(existing_launch)

    checks = [
      %{
        key: "ownerOrOperatorAuthorized",
        passed: owner_or_operator?,
        message:
          if(owner_or_operator?,
            do: "This linked wallet controls the ERC-8004 identity as owner or operator.",
            else:
              "This identity is only wallet-bound. Launching requires ERC-8004 owner or operator access."
          )
      },
      %{
        key: "noPriorSuccessfulLaunch",
        passed: not existing_launch?,
        message:
          if(existing_launch?,
            do: "This ERC-8004 identity already has an Agent Coin launch recorded.",
            else: "No prior Agent Coin launch is attached to this ERC-8004 identity."
          )
      }
    ]

    %{
      ready_to_launch: Enum.all?(checks, & &1.passed),
      resolved_lifecycle_run_id: identity.agent_id,
      stake_lock_id: nil,
      blocking_status_code: if(Enum.all?(checks, & &1.passed), do: "ready", else: "blocked"),
      blocking_status_message:
        if(Enum.all?(checks, & &1.passed),
          do: "ERC-8004 identity is ready for launch.",
          else: "Resolve the highlighted launch blocker before continuing."
        ),
      checks: checks
    }
  end

  defp launch_blockers(%{checks: checks}) do
    checks
    |> Enum.filter(fn check -> check.key in @eligibility_check_keys and not check.passed end)
    |> Enum.map(& &1.message)
  end

  defp active_launch_record?(%{launch_status: status}),
    do: status in ["queued", "running", "succeeded"]

  defp active_launch_record?(%{status: status}), do: status in ["queued", "running", "succeeded"]
  defp active_launch_record?(_record), do: false

  defp ensure_agent_eligible(%{state: "eligible"}), do: :ok
  defp ensure_agent_eligible(agent), do: {:error, {:agent_not_eligible, agent}}

  defp fetch_auction_for_bid(auction_id, current_human) do
    case get_auction(auction_id, current_human) do
      nil -> {:error, :auction_not_found}
      auction -> {:ok, auction}
    end
  end

  defp local_bid_id(auction_id, onchain_bid_id) when is_integer(onchain_bid_id) do
    "#{auction_id}:#{onchain_bid_id}"
  end

  defp build_bid_quote_snapshot(attrs, snapshot) do
    %{
      "quote_mode" => "onchain_exact_v1",
      "current_clearing_price" =>
        Map.get(attrs, "current_clearing_price") ||
          q96_price_to_string(snapshot.checkpoint.clearing_price_q96),
      "estimated_tokens_if_end_now" => Map.get(attrs, "estimated_tokens_if_end_now"),
      "estimated_tokens_if_no_other_bids_change" =>
        Map.get(attrs, "estimated_tokens_if_no_other_bids_change"),
      "inactive_above_price" => Map.get(attrs, "inactive_above_price"),
      "status_band" => Map.get(attrs, "status_band"),
      "projected_clearing_price" => Map.get(attrs, "projected_clearing_price")
    }
  end

  defp serialize_tx_request(%{chain_id: chain_id, to: to, value_hex: value_hex, data: data}) do
    %{
      chain_id: chain_id,
      to: to,
      value: value_hex,
      data: data
    }
  end

  defp serialize_action_request(nil), do: nil

  defp serialize_action_request(%{tx_request: tx_request} = action) do
    action
    |> Map.drop([:tx_request])
    |> Map.put(:tx_request, serialize_tx_request(tx_request))
  end

  defp fallback_bid_clearing_price(auction, bid) do
    if auction[:current_clearing_price],
      do: auction.current_clearing_price,
      else: decimal_string(bid.current_clearing_price)
  end

  defp next_action_label(nil, "claimable"), do: "Claim purchased tokens."
  defp next_action_label(nil, "exited"), do: "Position has already exited."
  defp next_action_label(nil, "claimed"), do: "Tokens already claimed."
  defp next_action_label(nil, "inactive"), do: "Monitor the auction until an exit becomes valid."
  defp next_action_label(nil, _status), do: "No wallet action available yet."

  defp next_action_label(%{claim_action: %{}} = _market_position, _status),
    do: "Claim purchased tokens now."

  defp next_action_label(%{exit_action: %{type: :exit_partially_filled_bid}}, _status),
    do: "Exit this bid with checkpoint hints."

  defp next_action_label(%{exit_action: %{type: :exit_bid}}, _status),
    do: "Exit this bid and settle the refund."

  defp next_action_label(_market_position, "inactive"),
    do: "Outbid for now. Exit becomes available only once the contract allows it."

  defp next_action_label(_market_position, "borderline"),
    do: "At the clearing boundary. Stay alert for displacement."

  defp next_action_label(_market_position, _status), do: "Bid is still participating."

  defp filter_positions(positions, filters) do
    case Map.get(filters, "status", Map.get(filters, :status)) do
      nil -> positions
      "" -> positions
      status -> Enum.filter(positions, &(&1.status == status))
    end
  end

  defp decorate_bid_position(%Bid{} = bid, current_human) do
    auction = get_auction(bid.auction_id, current_human) || %{}

    market_position =
      with %{auction_address: auction_address, chain_id: chain_id}
           when is_binary(auction_address) and is_integer(chain_id) <- auction,
           {:ok, snapshot} <- CCAContract.snapshot(chain_id, auction_address),
           {:ok, market_position} <- CCAMarket.sync_bid_position(snapshot, bid) do
        market_position
      else
        _ -> nil
      end

    derived_status =
      if market_position,
        do: market_position.current_status,
        else: derive_position_status(bid, auction)

    tx_actions =
      if market_position do
        %{
          exit: serialize_action_request(market_position.exit_action),
          claim: serialize_action_request(market_position.claim_action)
        }
      else
        %{exit: nil, claim: nil}
      end

    %{
      bid_id: bid.bid_id,
      onchain_bid_id: bid.onchain_bid_id,
      auction_id: bid.auction_id,
      agent_id: bid.agent_id,
      agent_name: bid.agent_name,
      chain: bid.network,
      status: derived_status,
      amount: decimal_string(bid.amount),
      max_price: decimal_string(bid.max_price),
      current_clearing_price:
        if(market_position,
          do: q96_price_to_string(market_position.current_clearing_price_q96),
          else: fallback_bid_clearing_price(auction, bid)
        ),
      estimated_tokens_if_end_now: decimal_string(bid.estimated_tokens_if_end_now, 2),
      estimated_tokens_if_no_other_bids_change:
        decimal_string(bid.estimated_tokens_if_no_other_bids_change, 2),
      inactive_above_price: decimal_string(bid.inactive_above_price),
      tokens_filled:
        if(market_position,
          do: token_units_to_string(market_position.onchain_bid.tokens_filled_units),
          else: "0"
        ),
      next_action_label: next_action_label(market_position, derived_status),
      tx_actions: tx_actions,
      auction: auction,
      inserted_at: iso(bid.inserted_at)
    }
  end

  defp derive_position_status(%Bid{claimed_at: %DateTime{}}, _auction), do: "claimed"
  defp derive_position_status(%Bid{exited_at: %DateTime{}}, _auction), do: "exited"

  defp derive_position_status(%Bid{} = _bid, %{status: status})
       when status in ["settled", "pending-claim"],
       do: "claimable"

  defp derive_position_status(%Bid{} = bid, auction) do
    clearing =
      parse_decimal(
        auction[:current_clearing_price] || decimal_string(bid.current_clearing_price)
      )

    compare = Decimal.compare(bid.max_price, clearing)

    cond do
      compare == :lt ->
        "inactive"

      Decimal.compare(bid.max_price, Decimal.mult(clearing, decimal("1.03"))) == :lt ->
        "borderline"

      true ->
        "active"
    end
  end

  defp ensure_bid_belongs_to_owner(%Bid{owner_address: owner_address}, wallet_address) do
    if owner_address == normalize_address(wallet_address), do: :ok, else: {:error, :forbidden}
  end

  defp parse_onchain_bid_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_onchain_bid_id}
    end
  end

  defp parse_onchain_bid_id(_value), do: {:error, :invalid_onchain_bid_id}

  defp filter_auctions(auctions, filters) do
    auctions
    |> maybe_filter_status(Map.get(filters, "status", Map.get(filters, :status)))
    |> maybe_filter_chain(Map.get(filters, "chain", Map.get(filters, :chain)))
    |> maybe_filter_mine(Map.get(filters, "mine_only", Map.get(filters, :mine_only)))
  end

  defp maybe_filter_status(auctions, nil), do: auctions
  defp maybe_filter_status(auctions, ""), do: auctions

  defp maybe_filter_status(auctions, "active"),
    do: Enum.filter(auctions, &(&1.status in ["active", "ending-soon"]))

  defp maybe_filter_status(auctions, "launched"),
    do: Enum.filter(auctions, &(&1.status in ["active", "ending-soon"]))

  defp maybe_filter_status(auctions, "expired"),
    do: Enum.filter(auctions, &(&1.status in ["settled", "pending-claim"]))

  defp maybe_filter_status(auctions, status), do: Enum.filter(auctions, &(&1.status == status))

  defp maybe_filter_chain(auctions, nil), do: auctions
  defp maybe_filter_chain(auctions, ""), do: auctions

  defp maybe_filter_chain(auctions, chain) do
    Enum.filter(auctions, &(&1.network == chain or &1.chain_family == chain))
  end

  defp maybe_filter_mine(auctions, value) when value in [true, "true", "1"],
    do: Enum.filter(auctions, &(&1.your_bid_status not in [nil, "none"]))

  defp maybe_filter_mine(auctions, _value), do: auctions

  defp sort_auctions(auctions, filters) do
    case Map.get(filters, "sort", Map.get(filters, :sort, "hottest")) do
      "recent" ->
        Enum.sort_by(auctions, &(&1.started_at || ""), :desc)

      "recently_launched" ->
        Enum.sort_by(auctions, &(&1.started_at || ""), :desc)

      "expired" ->
        Enum.sort_by(auctions, &{&1.status != "settled", -parse_float(&1.total_bid_volume)}, :asc)

      _ ->
        Enum.sort_by(auctions, &{-&1.sort_score, &1.ends_at || ""})
    end
  end

  defp serialize_auction(%Auction{} = auction, current_human) do
    public_id = auction.source_job_id || "auc_#{auction.id}"
    your_bid_status = current_bid_status(public_id, current_human)
    chain = chain_config(auction.chain_id)
    live_snapshot = load_live_snapshot(auction)
    clearing_q96 = live_snapshot[:clearing_price_q96]
    currency_raised_wei = live_snapshot[:currency_raised_wei]

    total_bid_volume =
      if(is_integer(currency_raised_wei),
        do: wei_to_float(currency_raised_wei),
        else: parse_float(auction.raised_currency)
      )

    %{
      id: public_id,
      agent_id: auction.agent_id,
      agent_name: auction.agent_name,
      symbol: auction_symbol(auction, public_id),
      owner_address: auction.owner_address,
      auction_address: auction.auction_address,
      token_address: auction.token_address,
      network: auction.network,
      chain: if(chain, do: chain.label, else: auction.network),
      chain_family: if(chain, do: chain.family, else: "unknown"),
      chain_id: auction.chain_id,
      status: auction.status,
      started_at: iso(auction.started_at),
      ends_at: iso(auction.ends_at),
      claim_at: iso(auction.claim_at),
      bidders: auction.bidders,
      raised_currency: auction.raised_currency,
      target_currency: auction.target_currency,
      progress_percent: auction.progress_percent,
      metrics_updated_at: iso(auction.metrics_updated_at),
      metrics_source:
        if(live_snapshot != %{},
          do: "onchain",
          else: if(auction.metrics_updated_at, do: "live", else: "fallback")
        ),
      quote_mode: if(live_snapshot != %{}, do: "onchain_exact_v1", else: "approximate_preview"),
      current_clearing_price:
        if(is_integer(clearing_q96),
          do: q96_price_to_string(clearing_q96),
          else: decimal_string(derived_clearing_price(auction))
        ),
      total_bid_volume:
        if(is_integer(currency_raised_wei),
          do: wei_to_string(currency_raised_wei),
          else: decimal_string(decimal(total_bid_volume))
        ),
      sort_score: hottest_score(total_bid_volume, auction.bidders, auction.started_at),
      notes: auction.notes,
      uniswap_url: auction.uniswap_url,
      your_bid_status: your_bid_status
    }
  end

  defp get_auction_by_address(network, auction_address, _current_human) do
    Repo.get_by(Auction, network: network, auction_address: auction_address)
    |> case do
      nil ->
        nil

      auction ->
        serialize_auction(auction, nil)
    end
  rescue
    _ -> nil
  end

  defp current_bid_status(auction_id, %HumanUser{} = human) do
    wallet_address = normalize_address(human.wallet_address)

    bid =
      Repo.one(
        from bid in Bid,
          where: bid.owner_address == ^wallet_address and bid.auction_id == ^auction_id,
          order_by: [desc: bid.inserted_at],
          limit: 1
      )

    auction =
      Repo.one(
        from auction in Auction,
          where: fragment("coalesce(?, '')", auction.source_job_id) == ^auction_id,
          limit: 1
      )

    case {bid, auction} do
      {nil, _} ->
        "none"

      {%Bid{} = tracked_bid, %Auction{} = tracked_auction} ->
        with {:ok, snapshot} <-
               CCAContract.snapshot(tracked_auction.chain_id, tracked_auction.auction_address),
             {:ok, market_position} <- CCAMarket.sync_bid_position(snapshot, tracked_bid) do
          market_position.current_status
        else
          _ ->
            derive_position_status(tracked_bid, %{
              current_clearing_price: decimal_string(tracked_bid.current_clearing_price)
            })
        end

      {%Bid{} = tracked_bid, _} ->
        derive_position_status(tracked_bid, %{
          current_clearing_price: decimal_string(tracked_bid.current_clearing_price)
        })
    end
  rescue
    _ -> "none"
  end

  defp current_bid_status(_auction_id, _human), do: nil

  defp auction_symbol(auction, public_id) do
    case auction.notes do
      notes when is_binary(notes) ->
        if String.starts_with?(notes, "$") do
          notes
        else
          fallback_auction_symbol(public_id)
        end

      _ ->
        fallback_auction_symbol(public_id)
    end
  end

  defp fallback_auction_symbol(public_id) do
    suffix =
      public_id
      |> String.split("_")
      |> List.last()
      |> String.upcase()

    "$" <> suffix
  end

  defp hottest_score(total_bid_volume, bidders, started_at) do
    age_hours =
      case started_at do
        %DateTime{} = datetime -> max(DateTime.diff(DateTime.utc_now(), datetime, :hour), 1)
        _ -> 24
      end

    total_bid_volume * 8.0 + bidders * 14 - age_hours * 2
  end

  defp derived_clearing_price(%Auction{} = auction) do
    base = decimal("0.0061")
    multiplier = decimal(Float.to_string(1 + min(auction.progress_percent, 100) / 250))
    Decimal.round(Decimal.mult(base, multiplier), 6)
  end

  defp maybe_record_external_launch(job) do
    now = DateTime.utc_now()
    launch_id = "atl_" <> Ecto.UUID.generate()

    attrs = %{
      launch_id: launch_id,
      owner_address: job.owner_address,
      agent_id: job.agent_id,
      lifecycle_run_id: job.lifecycle_run_id,
      chain_id: job.chain_id,
      total_supply: job.total_supply,
      vesting_beneficiary: job.vesting_beneficiary,
      beneficiary_confirmed_at: now,
      vesting_start_at: now,
      vesting_end_at: DateTime.add(now, 365 * 24 * 60 * 60, :second),
      launch_status: "queued",
      launch_job_id: job.job_id,
      metadata: %{
        "source" => "autolaunch",
        "token_name" => job.token_name,
        "token_symbol" => job.token_symbol
      }
    }

    %TokenLaunch{}
    |> TokenLaunch.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: [launch_status: "queued", updated_at: now]],
      conflict_target: :launch_job_id
    )
  rescue
    _ -> :ok
  end

  defp mark_external_launch(job_id, status, attrs) do
    if launch = Repo.get_by(TokenLaunch, launch_job_id: job_id) do
      attrs =
        case Map.get(attrs, :metadata) do
          metadata when is_map(metadata) ->
            Map.put(attrs, :metadata, Map.merge(launch.metadata || %{}, metadata))

          _ ->
            attrs
        end

      launch
      |> TokenLaunch.changeset(Map.put(attrs, :launch_status, status))
      |> Repo.update()
    else
      :ok
    end
  rescue
    _ -> :ok
  end

  defp persist_auction(job, result) do
    now = DateTime.utc_now()

    attrs = %{
      source_job_id: "auc_" <> String.replace_prefix(job.job_id, "job_", ""),
      agent_id: job.agent_id,
      agent_name: job.agent_name || job.agent_id,
      owner_address: job.owner_address,
      auction_address: result.auction_address,
      token_address: result.token_address,
      network: job.network,
      chain_id: job.chain_id,
      status: "active",
      started_at: now,
      ends_at: DateTime.add(now, 36 * 60 * 60, :second),
      bidders: 0,
      raised_currency: "0 ETH",
      target_currency: "150 ETH",
      progress_percent: 0,
      metrics_updated_at: now,
      notes: job.token_symbol || job.launch_notes,
      uniswap_url: result.uniswap_url
    }

    {:ok, auction} =
      Repo.insert(
        Auction.changeset(%Auction{}, attrs),
        conflict_target: [:network, :auction_address],
        on_conflict: [set: Keyword.drop(Map.to_list(attrs), [:source_job_id])],
        returning: true
      )

    auction
  end

  defp run_launch(job) do
    if mock_deploy?(), do: simulate_launch(job), else: run_command_launch(job)
  end

  defp simulate_launch(job) do
    :timer.sleep(1_200)

    suffix =
      Ecto.UUID.generate()
      |> String.replace("-", "")
      |> String.slice(0, 40)

    auction_address = "0x" <> suffix
    token_address = "0x" <> String.reverse(suffix)
    hook_address = "0x" <> String.duplicate("b", 40)
    fee_vault_address = "0x" <> String.duplicate("c", 40)
    official_pool_id = "0x" <> String.duplicate("d", 64)

    {:ok,
     %{
       auction_address: auction_address,
       token_address: token_address,
       hook_address: hook_address,
       fee_vault_address: fee_vault_address,
       official_pool_id: official_pool_id,
       tx_hash: "0x" <> String.duplicate("a", 64),
       uniswap_url: to_uniswap_url(job.chain_id, token_address),
       stdout_tail:
         "CCA_RESULT_JSON:{\"auctionAddress\":\"#{auction_address}\",\"tokenAddress\":\"#{token_address}\",\"hookAddress\":\"#{hook_address}\",\"feeVaultAddress\":\"#{fee_vault_address}\",\"poolId\":\"#{official_pool_id}\",\"txHash\":\"0x#{String.duplicate("a", 64)}\"}",
       stderr_tail: ""
     }}
  end

  defp run_command_launch(job) do
    binary = deploy_binary()
    workdir = deploy_workdir()
    script_target = deploy_script_target()
    rpc_url = deploy_rpc_url(job.chain_id)
    deploy_error = deploy_env_error(job.chain_id)

    cond do
      blank?(rpc_url) ->
        {:error, "Missing deploy RPC URL for #{job.network}.",
         %{stdout_tail: "", stderr_tail: ""}}

      deploy_error ->
        {:error, deploy_error, %{stdout_tail: "", stderr_tail: ""}}

      true ->
        args =
          ["script", script_target, "--rpc-url", rpc_url] ++
            credentials_args() ++ broadcast_args(job)

        task =
          Task.async(fn ->
            System.cmd(binary, args,
              cd: workdir,
              env: command_env(job),
              stderr_to_stdout: true
            )
          end)

        case Task.yield(task, 180_000) || Task.shutdown(task, :brutal_kill) do
          {:ok, {output, 0}} ->
            parse_launch_output(job, output)

          {:ok, {output, exit_code}} ->
            {:error, "Forge exited with status #{exit_code}.",
             %{stdout_tail: trim_tail(output), stderr_tail: ""}}

          nil ->
            {:error, "Forge timed out while waiting for deployment.",
             %{stdout_tail: "", stderr_tail: ""}}
        end
    end
  rescue
    error ->
      {:error, Exception.message(error), %{stdout_tail: "", stderr_tail: ""}}
  end

  defp parse_launch_output(job, output) do
    marker = deploy_output_marker()

    with true <- String.contains?(output, marker),
         [_prefix, json_line | _] <- String.split(output, marker, parts: 2),
         [line | _] <- String.split(json_line, ~r/\r?\n/, trim: true),
         {:ok, parsed} <- Jason.decode(String.trim(line)) do
      auction_address = normalize_address(Map.get(parsed, "auctionAddress"))
      token_address = normalize_address(Map.get(parsed, "tokenAddress"))
      hook_address = normalize_address(Map.get(parsed, "hookAddress"))
      fee_vault_address = normalize_address(Map.get(parsed, "feeVaultAddress"))
      official_pool_id = normalize_pool_id(Map.get(parsed, "poolId"))
      tx_hash = Map.get(parsed, "txHash")

      if blank?(auction_address) do
        {:error, "Deployment output did not include auctionAddress.",
         %{stdout_tail: trim_tail(output), stderr_tail: ""}}
      else
        {:ok,
         %{
           auction_address: auction_address,
           token_address: token_address,
           hook_address: hook_address,
           fee_vault_address: fee_vault_address,
           official_pool_id: official_pool_id,
           tx_hash: tx_hash,
           uniswap_url: to_uniswap_url(job.chain_id, token_address),
           stdout_tail: trim_tail(output),
           stderr_tail: ""
         }}
      end
    else
      _ ->
        {:error, "Deployment output missing deterministic marker #{marker}.",
         %{stdout_tail: trim_tail(output), stderr_tail: ""}}
    end
  end

  defp time_remaining_seconds(nil), do: 0

  defp time_remaining_seconds(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, datetime, _} -> max(DateTime.diff(datetime, DateTime.utc_now(), :second), 0)
      _ -> 0
    end
  end

  defp serialize_job(job) do
    chain = chain_config(job.chain_id)

    %{
      job_id: job.job_id,
      owner_address: job.owner_address,
      agent_id: job.agent_id,
      agent_name: job.agent_name,
      token_name: job.token_name,
      token_symbol: job.token_symbol,
      treasury_address: job.treasury_address,
      network: job.network,
      chain_id: job.chain_id,
      chain_family: if(chain, do: chain.family, else: nil),
      chain_label: if(chain, do: chain.label, else: job.network),
      status: job.status,
      step: job.step,
      error_message: job.error_message,
      broadcast: job.broadcast,
      total_supply: job.total_supply,
      launch_notes: job.launch_notes,
      nonce: job.siwa_nonce,
      issued_at: iso(job.issued_at),
      lifecycle_run_id: job.lifecycle_run_id,
      vesting_beneficiary: job.vesting_beneficiary,
      auction_address: job.auction_address,
      token_address: job.token_address,
      hook_address: job.hook_address,
      fee_vault_address: job.fee_vault_address,
      official_pool_id: job.official_pool_id,
      tx_hash: job.tx_hash,
      uniswap_url: job.uniswap_url,
      started_at: iso(job.started_at),
      finished_at: iso(job.finished_at),
      created_at: iso(job.inserted_at),
      updated_at: iso(job.updated_at),
      command_summary: %{
        binary: job.deploy_binary,
        script_target: job.script_target,
        cwd: job.deploy_workdir,
        broadcast: job.broadcast,
        rpc_host: job.rpc_host
      },
      logs: %{
        stdout_tail: job.stdout_tail || "",
        stderr_tail: job.stderr_tail || ""
      }
    }
  end

  defp ensure_authenticated_human(%HumanUser{privy_user_id: privy_user_id})
       when is_binary(privy_user_id), do: :ok

  defp ensure_authenticated_human(_human), do: {:error, :unauthorized}

  defp ensure_wallet_matches_human(%HumanUser{} = human, wallet) do
    normalized_wallet = normalize_address(wallet)

    if normalized_wallet in linked_wallet_addresses(human),
      do: :ok,
      else: {:error, :wallet_mismatch}
  end

  defp normalize_launch_chain(attrs) do
    with {:ok, chain_id} <- normalize_chain_id(Map.get(attrs, "chain_id")),
         {:ok, config} <- fetch_chain_config(chain_id) do
      {:ok, config}
    end
  end

  defp deploy_binary do
    Application.get_env(:autolaunch, :launch, [])
    |> Keyword.get(:deploy_binary, "forge")
  end

  defp deploy_workdir do
    Application.get_env(:autolaunch, :launch, [])
    |> Keyword.get(:deploy_workdir, "")
  end

  defp deploy_script_target do
    Application.get_env(:autolaunch, :launch, [])
    |> Keyword.get(:deploy_script_target, "")
  end

  defp deploy_output_marker do
    Application.get_env(:autolaunch, :launch, [])
    |> Keyword.get(:deploy_output_marker, "CCA_RESULT_JSON:")
  end

  defp deploy_rpc_url(chain_id) do
    config = launch_config()

    case chain_id do
      1 -> Keyword.get(config, :eth_mainnet_rpc_url, "")
      11_155_111 -> Keyword.get(config, :eth_sepolia_rpc_url, "")
      _ -> ""
    end
  end

  defp deploy_rpc_host(chain_id) do
    case deploy_rpc_url(chain_id) do
      nil ->
        nil

      "" ->
        nil

      url ->
        case URI.parse(url) do
          %URI{host: host} when is_binary(host) -> host
          _ -> "custom"
        end
    end
  end

  defp mock_deploy? do
    launch_config()
    |> Keyword.get(:mock_deploy, false)
  end

  defp credentials_args do
    config = launch_config()
    account = Keyword.get(config, :deploy_account, "")
    password = Keyword.get(config, :deploy_password, "")
    private_key = Keyword.get(config, :deploy_private_key, "")

    cond do
      account != "" and password != "" -> ["--account", account, "--password", password]
      account != "" -> ["--account", account]
      private_key != "" -> ["--private-key", private_key]
      true -> []
    end
  end

  defp broadcast_args(%Job{broadcast: true}), do: ["--broadcast"]
  defp broadcast_args(_job), do: []

  defp command_env(job) do
    [
      {"AUTOLAUNCH_OWNER_ADDRESS", job.owner_address},
      {"AUTOLAUNCH_AGENT_ID", job.agent_id},
      {"AUTOLAUNCH_AGENT_NAME", job.agent_name || ""},
      {"AUTOLAUNCH_TOKEN_NAME", job.token_name || ""},
      {"AUTOLAUNCH_TOKEN_SYMBOL", job.token_symbol || ""},
      {"AUTOLAUNCH_TOTAL_SUPPLY", job.total_supply},
      {"AUTOLAUNCH_TREASURY_ADDRESS", job.treasury_address || ""},
      {"AUTOLAUNCH_LIFECYCLE_RUN_ID", job.lifecycle_run_id || ""},
      {"AUTOLAUNCH_LAUNCH_NOTES", job.launch_notes || ""},
      {"AUTOLAUNCH_NETWORK", job.network},
      {"AUTOLAUNCH_CHAIN_ID", Integer.to_string(job.chain_id)},
      {"REGENT_MULTISIG_ADDRESS", deploy_regent_multisig_address()},
      {"FACTORY_ADDRESS", deploy_factory_address(job.chain_id)},
      {"UNISWAP_V4_POOL_MANAGER", deploy_pool_manager_address(job.chain_id)}
    ]
  end

  defp to_uniswap_url(chain_id, token_address) do
    case chain_config(chain_id) do
      %{uniswap_network: network} when is_binary(network) and is_binary(token_address) ->
        "https://app.uniswap.org/explore/tokens/#{network}/#{token_address}"

      _ ->
        nil
    end
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp truthy?(value), do: value in [true, "true", "1", 1, "on", "yes"]

  defp normalize_address(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: String.downcase(trimmed)
  end

  defp normalize_address(_value), do: nil

  defp linked_wallet_addresses(%HumanUser{} = human) do
    [human.wallet_address | human.wallet_addresses || []]
    |> Enum.map(&normalize_address/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp linked_wallet_addresses(_human), do: []

  defp primary_wallet_address(%HumanUser{} = human) do
    case linked_wallet_addresses(human) do
      [wallet | _rest] -> wallet
      [] -> nil
    end
  end

  defp normalize_pool_id(value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(~r/^0x[0-9a-fA-F]{64}$/, trimmed) do
      String.downcase(trimmed)
    else
      nil
    end
  end

  defp normalize_pool_id(_value), do: nil

  defp normalize_chain_id(value) when is_integer(value) do
    if value in [1, 11_155_111], do: {:ok, value}, else: {:error, :invalid_chain_id}
  end

  defp normalize_chain_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> normalize_chain_id(parsed)
      _ -> {:error, :invalid_chain_id}
    end
  end

  defp normalize_chain_id(_value), do: {:error, :invalid_chain_id}

  defp ensure_chain_id_matches_preview(chain_id, preview_chain_id)
       when chain_id == preview_chain_id,
       do: :ok

  defp ensure_chain_id_matches_preview(_chain_id, _preview_chain_id),
    do: {:error, :invalid_chain_id}

  defp normalize_total_supply(value) when is_binary(value) do
    trimmed = String.trim(value)
    if Regex.match?(~r/^\d+$/, trimmed), do: trimmed, else: "100000000000000000000000000000"
  end

  defp normalize_total_supply(_value), do: "100000000000000000000000000000"

  defp required_text(value, max_length, error_atom) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: {:error, error_atom}, else: {:ok, String.slice(value, 0, max_length)}
  end

  defp required_text(_value, _max_length, error_atom), do: {:error, error_atom}

  defp required_address(value) do
    case normalize_address(value) do
      address when is_binary(address) ->
        if Regex.match?(~r/^0x[0-9a-f]{40}$/, address) do
          {:ok, address}
        else
          {:error, :invalid_wallet_address}
        end

      _ ->
        {:error, :invalid_wallet_address}
    end
  end

  defp required_decimal(value, error_atom) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {decimal, ""} -> {:ok, decimal}
      _ -> {:error, error_atom}
    end
  end

  defp required_decimal(value, _error_atom) when is_number(value), do: {:ok, decimal(value)}
  defp required_decimal(_value, error_atom), do: {:error, error_atom}

  defp required_tx_hash(value) when is_binary(value) do
    tx_hash = String.downcase(String.trim(value))

    if Regex.match?(~r/^0x[0-9a-f]{64}$/, tx_hash) do
      {:ok, tx_hash}
    else
      {:error, :invalid_transaction_hash}
    end
  end

  defp required_tx_hash(_value), do: {:error, :invalid_transaction_hash}

  defp normalize_optional_text(value, max_length) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: String.slice(value, 0, max_length)
  end

  defp normalize_optional_text(_value, _max_length), do: nil

  defp parse_issued_at(value) when is_binary(value) do
    case DateTime.from_iso8601(String.trim(value)) do
      {:ok, datetime, _offset} -> datetime
      _ -> DateTime.utc_now()
    end
  end

  defp parse_issued_at(_value), do: DateTime.utc_now()

  defp trim_tail(output) when is_binary(output) do
    String.slice(output, max(String.length(output) - 20_000, 0), 20_000)
  end

  defp blank?(value), do: value in [nil, ""]

  defp launch_config do
    Application.get_env(:autolaunch, :launch, [])
  end

  defp fetch_chain_config(chain_id) do
    case chain_config(chain_id) do
      nil -> {:error, :invalid_chain_id}
      config -> {:ok, config}
    end
  end

  defp chain_config(chain_id), do: Map.get(@chain_configs, chain_id)

  defp chain_config!(chain_id) do
    case chain_config(chain_id) do
      nil -> raise ArgumentError, "unsupported chain id #{inspect(chain_id)}"
      config -> config
    end
  end

  defp deploy_factory_address(chain_id) do
    case chain_id do
      1 -> Keyword.get(launch_config(), :eth_mainnet_factory_address, "")
      11_155_111 -> Keyword.get(launch_config(), :eth_sepolia_factory_address, "")
      _ -> ""
    end
  end

  defp deploy_pool_manager_address(chain_id) do
    case chain_id do
      1 -> Keyword.get(launch_config(), :eth_mainnet_pool_manager_address, "")
      11_155_111 -> Keyword.get(launch_config(), :eth_sepolia_pool_manager_address, "")
      _ -> ""
    end
  end

  defp deploy_regent_multisig_address do
    Keyword.get(
      launch_config(),
      :regent_multisig_address,
      "0x9fa152B0EAdbFe9A7c5C0a8e1D11784f22669a3e"
    )
  end

  defp deploy_env_error(chain_id) do
    with {:ok, chain} <- fetch_chain_config(chain_id) do
      cond do
        blank?(deploy_pool_manager_address(chain_id)) ->
          "Missing #{chain.label} Uniswap v4 pool manager address."

        blank?(deploy_factory_address(chain_id)) ->
          "Missing #{chain.label} CCA factory address."

        true ->
          nil
      end
    else
      _ -> "Unsupported deploy network."
    end
  end

  defp load_live_snapshot(%Auction{auction_address: auction_address, chain_id: chain_id})
       when is_binary(auction_address) and is_integer(chain_id) do
    case CCAContract.snapshot(chain_id, auction_address) do
      {:ok, snapshot} ->
        %{
          clearing_price_q96: snapshot.checkpoint.clearing_price_q96,
          currency_raised_wei: snapshot.currency_raised_wei,
          total_cleared_units: snapshot.total_cleared_units,
          is_graduated: snapshot.is_graduated
        }

      _ ->
        %{}
    end
  end

  defp load_live_snapshot(_auction), do: %{}

  defp parse_float(value) when is_binary(value) do
    value
    |> String.replace("ETH", "")
    |> String.replace(",", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {parsed, _} -> parsed
      _ -> 0.0
    end
  end

  defp parse_float(value) when is_number(value), do: value * 1.0
  defp parse_float(_value), do: 0.0

  defp parse_decimal(value) when is_binary(value), do: decimal(parse_float(value))
  defp parse_decimal(%Decimal{} = value), do: value
  defp parse_decimal(value) when is_number(value), do: decimal(value)
  defp parse_decimal(_value), do: decimal("0")

  defp decimal_from_string(nil), do: nil

  defp decimal_from_string(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp decimal_from_string(%Decimal{} = value), do: value
  defp decimal_from_string(_value), do: nil

  defp decimal(value) when is_binary(value), do: Decimal.new(value)
  defp decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp decimal(value) when is_integer(value), do: Decimal.new(value)

  defp decimal_to_wei(%Decimal{} = value) do
    scaled = Decimal.mult(value, Decimal.new("1000000000000000000"))

    if Decimal.equal?(scaled, Decimal.round(scaled, 0)) do
      {:ok, scaled |> Decimal.round(0) |> Decimal.to_integer()}
    else
      {:error, :invalid_amount_precision}
    end
  end

  defp decimal_price_to_q96(%Decimal{} = value) do
    scaled = Decimal.mult(value, Decimal.new("79228162514264337593543950336"))

    if Decimal.equal?(scaled, Decimal.round(scaled, 0)) do
      {:ok, scaled |> Decimal.round(0) |> Decimal.to_integer()}
    else
      {:ok, scaled |> Decimal.round(0) |> Decimal.to_integer()}
    end
  rescue
    _ -> {:error, :invalid_max_price}
  end

  defp q96_price_to_string(value) when is_integer(value) and value >= 0 do
    value
    |> Decimal.new()
    |> Decimal.div(Decimal.new("79228162514264337593543950336"))
    |> Decimal.round(12)
    |> Decimal.to_string(:normal)
  end

  defp q96_to_decimal(value) when is_integer(value) and value >= 0 do
    value
    |> Decimal.new()
    |> Decimal.div(Decimal.new("79228162514264337593543950336"))
    |> Decimal.round(12)
  end

  defp token_units_to_string(value) when is_integer(value) and value >= 0 do
    value
    |> Decimal.new()
    |> Decimal.div(Decimal.new("1000000000000000000"))
    |> Decimal.round(6)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp wei_to_string(value) when is_integer(value) and value >= 0 do
    value
    |> Decimal.new()
    |> Decimal.div(Decimal.new("1000000000000000000"))
    |> Decimal.round(6)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp wei_to_float(value) when is_integer(value), do: value / 1.0e18

  defp decimal_string(value, places \\ 4)

  defp decimal_string(%Decimal{} = value, places) do
    value
    |> Decimal.round(places)
    |> Decimal.to_string(:normal)
  end

  defp decimal_string(nil, _places), do: "0"
end
