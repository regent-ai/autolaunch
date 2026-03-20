defmodule AutolaunchWeb.LaunchLive do
  use AutolaunchWeb, :live_view

  alias Autolaunch.Launch

  @job_poll_ms 2_000

  def mount(_params, _session, socket) do
    current_human = socket.assigns[:current_human]
    agents = launch_module().list_agents(current_human)
    form = default_form(current_human)

    {:ok,
     socket
     |> assign(:page_title, "Launch")
     |> assign(:active_view, "launch")
     |> assign(:agents, agents)
     |> assign(:chain_options, launch_module().chain_options())
     |> assign(:selected_agent_id, nil)
     |> assign(:selected_agent, nil)
     |> assign(:readiness, nil)
     |> assign(:form, form)
     |> assign(:preview, nil)
     |> assign(:step, 1)
     |> assign(:launching, false)
     |> assign(:job_id, nil)
     |> assign(:current_job, nil)
     |> assign(:fee_split, launch_module().fee_split_summary())}
  end

  def handle_event("select_agent", %{"agent_id" => agent_id}, socket) do
    case Enum.find(socket.assigns.agents, &(&1.agent_id == agent_id or &1.id == agent_id)) do
      %{state: "eligible"} = agent ->
        readiness =
          launch_module().launch_readiness_for_agent(socket.assigns.current_human, agent.agent_id)

        selected_chain_id =
          case List.first(agent.supported_chains) do
            %{id: id} -> id
            _ -> socket.assigns.form["chain_id"]
          end

        form =
          socket.assigns.form
          |> Map.put("agent_id", agent.agent_id)
          |> Map.put("chain_id", selected_chain_id)

        {:noreply,
         socket
         |> assign(:selected_agent_id, agent.agent_id)
         |> assign(:selected_agent, agent)
         |> assign(:readiness, readiness)
         |> assign(:form, form)
         |> assign(:preview, nil)
         |> assign(:step, 2)}

      %{state: state} ->
        {:noreply, put_flash(socket, :error, "Agent is #{String.replace(state, "_", " ")}.")}

      nil ->
        {:noreply, put_flash(socket, :error, "Agent not found.")}
    end
  end

  def handle_event("form_changed", %{"launch" => attrs}, socket) do
    {:noreply, assign(socket, :form, Map.merge(socket.assigns.form, attrs))}
  end

  def handle_event("go_to_step", %{"step" => step}, socket) do
    target_step = normalize_step(step)
    {:noreply, assign(socket, :step, min(target_step, max_available_step(socket)))}
  end

  def handle_event("prepare_review", _params, socket) do
    case launch_module().preview_launch(socket.assigns.form, socket.assigns.current_human) do
      {:ok, preview} ->
        {:noreply, socket |> assign(:preview, preview) |> assign(:step, 3)}

      {:error, {:agent_not_eligible, _agent}} ->
        {:noreply, put_flash(socket, :error, "Selected agent is no longer eligible to launch.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Privy session required before launch.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, preview_error(reason))}
    end
  end

  def handle_event("launch_submitting", _params, socket) do
    {:noreply, assign(socket, :launching, true)}
  end

  def handle_event("launch_error", %{"message" => message}, socket) do
    {:noreply, socket |> assign(:launching, false) |> put_flash(:error, message)}
  end

  def handle_event("launch_queued", %{"job_id" => job_id}, socket) do
    if connected?(socket), do: Process.send_after(self(), {:poll_job, job_id}, 100)

    {:noreply,
     socket
     |> put_flash(:info, "Launch job queued.")
     |> assign(:launching, false)
     |> assign(:job_id, job_id)
     |> assign(:step, 4)}
  end

  def handle_info({:poll_job, job_id}, socket) do
    case launch_module().get_job_response(job_id) do
      %{job: job} = response ->
        socket = assign(socket, :current_job, response)

        if launch_module().terminal_status?(job.status) do
          flash =
            case job.status do
              "ready" -> put_flash(socket, :info, "Launch is live.")
              _ -> put_flash(socket, :error, job.error_message || "Launch job failed.")
            end

          {:noreply, flash}
        else
          Process.send_after(self(), {:poll_job, job_id}, @job_poll_ms)
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def render(assigns) do
    eligible_count = Enum.count(assigns.agents, &(&1.state == "eligible"))
    selected_agent = assigns.selected_agent
    current_reputation_prompt = current_reputation_prompt(assigns.preview, assigns.current_job)

    assigns =
      assigns
      |> assign(:eligible_count, eligible_count)
      |> assign(:selected_agent, selected_agent)
      |> assign(:current_reputation_prompt, current_reputation_prompt)

    ~H"""
    <.shell current_human={@current_human} active_view={@active_view}>
      <section id="launch-hero" class="al-hero al-panel" phx-hook="MissionMotion">
        <div>
          <p class="al-kicker">Guided Launch</p>
          <h2>Choose a launchable agent before you touch token settings.</h2>
          <p class="al-subcopy">
            The launch path starts with ERC-8004 eligibility because one identity can create only one
            Agent Coin. Token inputs appear only after the identity is cleared.
          </p>
        </div>

        <div class="al-stat-grid">
          <.stat_card title="Eligible agents" value={Integer.to_string(@eligible_count)} hint="Owner or operator access" />
          <.stat_card title="Fee split" value="2% total" hint="1% treasury + 1% Regent multisig" />
          <.stat_card title="Write path" value="Privy + SIWA" hint="Human identity plus wallet proof" />
        </div>
      </section>

      <section class="al-wizard-layout">
        <article class="al-panel al-main-panel">
          <div class="al-step-row">
            <.step_chip index={1} label="Choose agent" active={@step == 1} complete={@step > 1} />
            <.step_chip index={2} label="Configure token" active={@step == 2} complete={@step > 2} />
            <.step_chip index={3} label="Review and sign" active={@step == 3} complete={@step > 3} />
            <.step_chip index={4} label="Optional trust" active={@step == 4} complete={@step > 4} />
            <.step_chip index={5} label="Launch status" active={@step == 5} complete={false} />
          </div>

          <%= if @step == 1 do %>
            <div class="al-section-head">
              <div>
                <p class="al-kicker">Step 1</p>
                <h3>Choose an eligible agent</h3>
              </div>
            </div>

            <%= cond do %>
              <% is_nil(@current_human) -> %>
                <.empty_state
                  title="Connect with Privy to inspect your ERC-8004 identities."
                  body="Linked wallets are checked for ERC-8004 owner and operator access. Wallet-bound identities are shown separately but cannot launch by themselves."
                />
              <% @agents == [] -> %>
                <.empty_state
                  title="No ERC-8004 identities found for your linked wallets."
                  body="Connect a wallet that owns or operates an ERC-8004 identity, or mint a new identity first."
                />
              <% true -> %>
                <div class="al-agent-grid">
                  <%= for agent <- @agents do %>
                    <article class={["al-agent-card", agent.state == "eligible" && "is-selectable"]}>
                      <div class="al-agent-media">
                        <%= if agent.image_url do %>
                          <img src={agent.image_url} alt={agent.name} class="al-agent-image" />
                        <% else %>
                          <div class="al-agent-image al-agent-image--placeholder">
                            <span>ERC-8004</span>
                          </div>
                        <% end %>
                      </div>

                      <div class="al-agent-card-head">
                        <div>
                          <p class="al-kicker">{agent.source}</p>
                          <h3>{agent.name}</h3>
                          <p class="al-inline-note">{agent.agent_id}</p>
                        </div>
                        <.agent_state_badge state={agent.state} />
                      </div>

                      <div class="al-pill-row">
                        <span class={["al-network-badge", "al-access-badge"]}>{access_mode_label(agent.access_mode)}</span>
                        <span :for={chain <- agent.supported_chains} class="al-network-badge">{chain.short_label}</span>
                      </div>

                      <dl class="al-agent-meta">
                        <div>
                          <dt>Owner</dt>
                          <dd>{short_address(agent.owner_address)}</dd>
                        </div>
                        <div :if={(agent.operator_addresses || []) != []}>
                          <dt>Operators</dt>
                          <dd>{Enum.count(agent.operator_addresses)}</dd>
                        </div>
                        <div :if={agent.ens}>
                          <dt>ENS</dt>
                          <dd>{agent.ens}</dd>
                        </div>
                        <div>
                          <dt>Token ID</dt>
                          <dd>{agent.token_id}</dd>
                        </div>
                      </dl>

                      <p :if={agent.description} class="al-inline-note">{agent.description}</p>

                      <%= if agent.blocker_texts != [] do %>
                        <ul class="al-compact-list">
                          <li :for={blocker <- agent.blocker_texts}>{blocker}</li>
                        </ul>
                      <% else %>
                        <p class="al-inline-note">Launch path is clear for this ERC-8004 identity.</p>
                      <% end %>

                      <button
                        :if={agent.state == "eligible"}
                        type="button"
                        class="al-submit"
                        phx-click="select_agent"
                        phx-value-agent_id={agent.agent_id}
                      >
                        Use this agent
                      </button>

                      <div :if={agent.state != "eligible"} class="al-muted-box">
                        {disabled_agent_message(agent)}
                      </div>
                    </article>
                  <% end %>
                </div>
              <% end %>
          <% end %>

          <%= if @step == 2 do %>
            <div class="al-section-head">
              <div>
                <p class="al-kicker">Step 2</p>
                <h3>Configure token basics</h3>
              </div>
            </div>

            <form phx-change="form_changed" class="al-form">
              <input type="hidden" name="launch[agent_id]" value={@form["agent_id"]} />

              <div class="al-field-grid">
                <label>
                  <span>Name</span>
                  <input type="text" name="launch[token_name]" value={@form["token_name"]} placeholder="Agent Coin Name" />
                </label>
                <label>
                  <span>Symbol</span>
                  <input type="text" name="launch[token_symbol]" value={@form["token_symbol"]} placeholder="AGENT-N" />
                </label>
                <label>
                  <span>Chain</span>
                  <select name="launch[chain_id]">
                    <option
                      :for={chain <- @chain_options}
                      value={chain.id}
                      selected={to_string(chain.id) == to_string(@form["chain_id"])}
                    >
                      {chain.label}
                    </option>
                  </select>
                </label>
                <label>
                  <span>Treasury address</span>
                  <input
                    type="text"
                    name="launch[treasury_address]"
                    value={@form["treasury_address"]}
                    placeholder="0x..."
                  />
                </label>
                <label>
                  <span>Total supply</span>
                  <input type="text" name="launch[total_supply]" value={@form["total_supply"]} />
                </label>
              </div>

              <label>
                <span>Launch notes</span>
                <textarea name="launch[launch_notes]" rows="4">{@form["launch_notes"]}</textarea>
              </label>
            </form>

            <div class="al-inline-banner">
              <strong>{@fee_split.headline}</strong>
              <p>One token per agent. The treasury address is locked into the launch configuration you sign.</p>
            </div>

            <div class="al-action-row">
              <button type="button" class="al-ghost" phx-click="go_to_step" phx-value-step="1">Back</button>
              <button type="button" class="al-submit" phx-click="prepare_review">Review economics and sign</button>
            </div>
          <% end %>

          <%= if @step == 3 do %>
            <div class="al-section-head">
              <div>
                <p class="al-kicker">Step 3</p>
                <h3>Review economics and sign</h3>
              </div>
            </div>

            <div id="launch-review-root" phx-hook="LaunchForm" class="al-review-stack">
              <input type="hidden" name="launch[agent_id]" value={@form["agent_id"]} />
              <input type="hidden" name="launch[token_name]" value={@form["token_name"]} />
              <input type="hidden" name="launch[token_symbol]" value={@form["token_symbol"]} />
              <input type="hidden" name="launch[chain_id]" value={@form["chain_id"]} />
              <input type="hidden" name="launch[treasury_address]" value={@form["treasury_address"]} />
              <input type="hidden" name="launch[total_supply]" value={@form["total_supply"]} />
              <textarea class="hidden" name="launch[launch_notes]"><%= @form["launch_notes"] %></textarea>

              <div class="al-review-grid">
                <div class="al-review-card">
                  <span>Agent</span>
                  <strong>{@selected_agent && @selected_agent.name}</strong>
                  <p>{@selected_agent && @selected_agent.agent_id}</p>
                </div>
                <div class="al-review-card">
                  <span>Token</span>
                  <strong>{@preview && @preview.token.name}</strong>
                  <p>{@preview && @preview.token.symbol}</p>
                </div>
                <div class="al-review-card">
                  <span>Chain</span>
                  <strong>{@preview && @preview.token.chain_label}</strong>
                  <p>Treasury {@preview && short_address(@preview.token.treasury_address)}</p>
                </div>
              </div>

              <div class="al-note-grid">
                <article class="al-note-card">
                  <p class="al-kicker">What happens next</p>
                  <ul class="al-compact-list">
                    <li :for={item <- (@preview && @preview.next_steps) || []}>{item}</li>
                  </ul>
                </article>
                <article class="al-note-card">
                  <p class="al-kicker">Permanence notes</p>
                  <ul class="al-compact-list">
                    <li :for={item <- (@preview && @preview.permanence_notes) || []}>{item}</li>
                  </ul>
                </article>
              </div>

              <article :if={@preview && @preview.reputation_prompt} class="al-note-card">
                <p class="al-kicker">Optional trust step</p>
                <strong>{@preview.reputation_prompt.prompt}</strong>
                <p>{@preview.reputation_prompt.warning}</p>
                <ul class="al-compact-list">
                  <li :for={instruction <- @preview.reputation_prompt.instructions}>{instruction}</li>
                </ul>
                <p class="al-inline-note">
                  The next screen gives the links and lets you skip this without blocking launch.
                </p>
              </article>

              <div class="al-action-row">
                <button type="button" class="al-ghost" phx-click="go_to_step" phx-value-step="2">Edit configuration</button>
                <button
                  type="button"
                  class={["al-submit", @launching && "is-disabled"]}
                  data-launch-submit
                  data-chain-id={@form["chain_id"]}
                  data-launch-endpoint={~p"/api/launch/jobs"}
                  data-nonce-endpoint="/v1/agent/siwa/nonce"
                  disabled={@launching}
                >
                  {if @launching, do: "Waiting for signature...", else: "Sign and queue launch"}
                </button>
              </div>
            </div>
          <% end %>

          <%= if @step == 4 do %>
            <div class="al-section-head">
              <div>
                <p class="al-kicker">Step 4</p>
                <h3>Optional reputation step</h3>
              </div>
            </div>

            <%= if @current_reputation_prompt do %>
              <div class="al-note-grid">
                <article class="al-note-card">
                  <p class="al-kicker">Optional</p>
                  <strong>{@current_reputation_prompt.prompt}</strong>
                  <p>{@current_reputation_prompt.warning}</p>
                  <ul class="al-compact-list">
                    <li :for={instruction <- @current_reputation_prompt.instructions}>
                      {instruction}
                    </li>
                  </ul>
                </article>

                <article
                  :for={action <- @current_reputation_prompt.actions}
                  class="al-note-card"
                >
                  <p class="al-kicker">{reputation_action_status(action.status)}</p>
                  <strong>{action.label}</strong>
                  <p>{action.note}</p>
                  <div class="al-pill-row">
                    <.link
                      :if={action.action_url}
                      navigate={action.action_url}
                      class="al-cta-link"
                    >
                      {reputation_action_cta(action)}
                    </.link>
                  </div>
                </article>

                <article :if={@current_job} class="al-note-card">
                  <p class="al-kicker">Launch job</p>
                  <ul class="al-compact-list">
                    <li>Status: <strong>{@current_job.job.status}</strong></li>
                    <li>Step: <strong>{@current_job.job.step}</strong></li>
                    <li>Job id: <strong>{@current_job.job.job_id}</strong></li>
                  </ul>
                </article>
              </div>

              <div class="al-action-row">
                <button type="button" class="al-ghost" phx-click="go_to_step" phx-value-step="5">
                  {@current_reputation_prompt.skip_label}
                </button>
                <button type="button" class="al-submit" phx-click="go_to_step" phx-value-step="5">
                  Continue to launch status
                </button>
              </div>
            <% else %>
              <p class="al-inline-note">Waiting for launch job response.</p>
            <% end %>
          <% end %>

          <%= if @step == 5 do %>
            <div class="al-section-head">
              <div>
                <p class="al-kicker">Step 5</p>
                <h3>Queued and processing</h3>
              </div>
            </div>

            <%= if @current_job do %>
              <div class="al-job-grid">
                <div>
                  <span>Status</span>
                  <strong>{@current_job.job.status}</strong>
                </div>
                <div>
                  <span>Step</span>
                  <strong>{@current_job.job.step}</strong>
                </div>
                <div>
                  <span>Chain</span>
                  <strong>{@current_job.job.chain_label || @current_job.job.network}</strong>
                </div>
                <div>
                  <span>Job id</span>
                  <strong>{@current_job.job.job_id}</strong>
                </div>
              </div>

              <div class="al-note-grid">
                <article class="al-note-card">
                  <p class="al-kicker">Timeline</p>
                  <ul class="al-compact-list">
                    <li>Queued for launch orchestration.</li>
                    <li>Waiting for deploy script and auction address.</li>
                    <li :if={@current_job.auction}>Auction page becomes available after deployment.</li>
                  </ul>
                </article>

                <article class="al-note-card">
                  <p class="al-kicker">Next action</p>
                  <%= if @current_job.auction do %>
                    <.link navigate={~p"/auctions/#{@current_job.auction.id}"} class="al-cta-link">
                      Open auction detail
                    </.link>
                  <% else %>
                    <p>Stay on this page while launch orchestration runs.</p>
                  <% end %>
                </article>

                <article :if={@current_job.job.reputation_prompt} class="al-note-card">
                  <p class="al-kicker">Trust follow-up</p>
                  <p>{@current_job.job.reputation_prompt.warning}</p>
                  <button type="button" class="al-network-badge" phx-click="go_to_step" phx-value-step="4">
                    Open optional trust step
                  </button>
                </article>

                <article
                  :if={
                    @current_job.job.hook_address || @current_job.job.fee_vault_address ||
                      @current_job.job.official_pool_id
                  }
                  class="al-note-card"
                >
                  <p class="al-kicker">Fee routing</p>
                  <ul class="al-compact-list">
                    <li :if={@current_job.job.hook_address}>
                      Hook: <strong>{@current_job.job.hook_address}</strong>
                    </li>
                    <li :if={@current_job.job.fee_vault_address}>
                      Fee vault: <strong>{@current_job.job.fee_vault_address}</strong>
                    </li>
                    <li :if={@current_job.job.official_pool_id}>
                      Pool id: <strong>{@current_job.job.official_pool_id}</strong>
                    </li>
                  </ul>
                </article>
              </div>
            <% else %>
              <p class="al-inline-note">Waiting for launch job response.</p>
            <% end %>
          <% end %>
        </article>

        <aside class="al-panel al-side-panel">
          <div class="al-section-head">
            <div>
              <p class="al-kicker">Launch readiness</p>
              <h3>
                {if @selected_agent, do: @selected_agent.name, else: "Choose an agent to inspect blockers"}
              </h3>
            </div>
          </div>

          <%= if @readiness do %>
            <div class="al-stat-grid">
              <.stat_card
                title="Checks passing"
                value={"#{Enum.count(@readiness.checks, & &1.passed)}/#{length(@readiness.checks)}"}
              />
              <.stat_card
                title="Identity"
                value={@readiness.resolved_lifecycle_run_id || "pending"}
                hint="ERC-8004 launch key"
              />
            </div>

            <ul class="al-checklist">
              <li :for={check <- @readiness.checks} class={["al-check-item", check.passed && "is-passed"]}>
                <span>{if check.passed, do: "Passed", else: "Blocked"}</span>
                <div>
                  <strong>{check.key}</strong>
                  <p>{check.message}</p>
                </div>
              </li>
            </ul>
          <% else %>
            <p class="al-inline-note">
              The launch sidebar stays focused on one identity at a time so you always see the exact ERC-8004 blocker set.
            </p>
          <% end %>
        </aside>
      </section>

      <.flash_group flash={@flash} />
    </.shell>
    """
  end

  defp default_form(nil) do
    %{
      "agent_id" => nil,
      "token_name" => "",
      "token_symbol" => "",
      "chain_id" => "1",
      "treasury_address" => "",
      "total_supply" => "100000000000000000000000000000",
      "launch_notes" => ""
    }
  end

  defp default_form(current_human) do
    default_form(nil)
    |> Map.put("treasury_address", current_human.wallet_address || "")
  end

  defp max_available_step(socket) do
    cond do
      socket.assigns.job_id -> 5
      socket.assigns.preview -> 3
      socket.assigns.selected_agent -> 2
      true -> 1
    end
  end

  defp normalize_step(step) when is_binary(step) do
    case Integer.parse(step) do
      {value, ""} -> value
      _ -> 1
    end
  end

  defp normalize_step(step) when is_integer(step), do: step
  defp normalize_step(_step), do: 1

  defp preview_error(:token_name_required), do: "Token name is required."
  defp preview_error(:token_symbol_required), do: "Token symbol is required."
  defp preview_error(:invalid_wallet_address), do: "Treasury address must be a valid EVM address."

  defp preview_error(:invalid_chain_id),
    do: "Select Ethereum mainnet or Ethereum Sepolia."

  defp preview_error(:agent_not_found), do: "Select an eligible agent first."
  defp preview_error(_reason), do: "Launch preview could not be prepared."

  defp short_address(nil), do: "pending"

  defp short_address(address) when is_binary(address) do
    address
    |> String.downcase()
    |> then(fn value ->
      if String.length(value) > 12 do
        String.slice(value, 0, 6) <> "..." <> String.slice(value, -4, 4)
      else
        value
      end
    end)
  end

  defp access_mode_label("owner"), do: "Owner"
  defp access_mode_label("operator"), do: "Operator"
  defp access_mode_label("wallet_bound"), do: "Wallet-bound"
  defp access_mode_label(_mode), do: "Unknown"

  defp disabled_agent_message(%{state: "already_launched"}),
    do: "This ERC-8004 identity already has an Agent Coin."

  defp disabled_agent_message(%{access_mode: "wallet_bound"}),
    do:
      "This identity is only wallet-bound. Launching requires ERC-8004 owner or operator access."

  defp disabled_agent_message(_agent),
    do: "Finish the missing setup before launch."

  defp launch_module do
    :autolaunch
    |> Application.get_env(:launch_live, [])
    |> Keyword.get(:launch_module, Launch)
  end

  defp current_reputation_prompt(_preview, %{job: %{reputation_prompt: prompt}})
       when is_map(prompt),
       do: prompt

  defp current_reputation_prompt(%{reputation_prompt: prompt}, _current_job) when is_map(prompt),
    do: prompt

  defp current_reputation_prompt(_preview, _current_job), do: nil

  defp reputation_action_status("complete"), do: "Complete"
  defp reputation_action_status("available"), do: "Ready now"
  defp reputation_action_status("pending"), do: "Available after launch"
  defp reputation_action_status(_status), do: "Optional"

  defp reputation_action_cta(%{key: "ens", completed: true}), do: "Review ENS planner"
  defp reputation_action_cta(%{key: "ens"}), do: "Open ENS planner"
  defp reputation_action_cta(%{key: "world", completed: true}), do: "Review World proof"
  defp reputation_action_cta(%{key: "world"}), do: "Open World proof"
  defp reputation_action_cta(_action), do: "Open"
end
