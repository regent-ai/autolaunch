defmodule AutolaunchWeb.SubjectLive do
  use AutolaunchWeb, :live_view

  alias Autolaunch.Launch
  alias AutolaunchWeb.Live.Refreshable
  alias AutolaunchWeb.SubjectLive.Components, as: SubjectComponents
  alias AutolaunchWeb.SubjectLive.Presenter

  @poll_ms 15_000
  def mount(%{"id" => subject_id}, _session, socket) do
    {:ok,
     socket
     |> Refreshable.schedule(@poll_ms)
     |> Refreshable.subscribe([:subjects, :regent, :system])
     |> assign(:page_title, "Token detail")
     |> assign(:active_view, "auction-detail")
     |> assign(:subject_id, subject_id)
     |> assign(:side_tab, "state")
     |> assign(:stake_form, %{"amount" => ""})
     |> assign(:unstake_form, %{"amount" => ""})
     |> assign(:pending_actions, %{})
     |> assign(:subject_market, load_subject_market(subject_id))
     |> assign_subject(subject_id)}
  end

  def handle_event("stake_changed", %{"stake" => attrs}, socket) do
    {:noreply, assign(socket, :stake_form, Map.merge(socket.assigns.stake_form, attrs))}
  end

  def handle_event("unstake_changed", %{"unstake" => attrs}, socket) do
    {:noreply, assign(socket, :unstake_form, Map.merge(socket.assigns.unstake_form, attrs))}
  end

  def handle_event("side_tab_changed", %{"tab" => tab}, socket) do
    if tab in Presenter.side_tabs() do
      {:noreply, assign(socket, :side_tab, tab)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("side_tab_changed", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "prepare_action",
        %{"action" => "sweep", "address" => ingress_address},
        socket
      ) do
    {:noreply, prepare_action(socket, {:sweep, ingress_address}, %{})}
  end

  def handle_event("prepare_action", %{"action" => "stake"}, socket) do
    {:noreply, prepare_action(socket, :stake, socket.assigns.stake_form)}
  end

  def handle_event("prepare_action", %{"action" => "unstake"}, socket) do
    {:noreply, prepare_action(socket, :unstake, socket.assigns.unstake_form)}
  end

  def handle_event("prepare_action", %{"action" => action}, socket) do
    case Presenter.action_to_atom(action) do
      {:ok, action} ->
        {:noreply, prepare_action(socket, action, %{})}

      :error ->
        {:noreply, put_flash(socket, :error, "That subject action is not available.")}
    end
  end

  def handle_event("wallet_tx_started", %{"message" => message}, socket) do
    {:noreply, Refreshable.wallet_started(socket, message)}
  end

  def handle_event("wallet_tx_registered", %{"message" => message}, socket) do
    {:noreply, Refreshable.wallet_registered(socket, message, &reload_subject/1)}
  end

  def handle_event("wallet_tx_error", %{"message" => message}, socket) do
    {:noreply, Refreshable.wallet_error(socket, message)}
  end

  def handle_info(:refresh, socket) do
    {:noreply, Refreshable.refresh(socket, @poll_ms, &reload_subject/1)}
  end

  def handle_info({:autolaunch_live_update, :changed}, socket) do
    {:noreply, reload_subject(socket)}
  end

  def render(assigns) do
    subject = assigns.subject
    recommended = Presenter.recommended_action(subject)
    wallet_position = Presenter.wallet_position(subject)
    ingress_accounts = if(subject, do: subject.ingress_accounts || [], else: [])

    assigns =
      assigns
      |> assign(:pending_actions, assigns.pending_actions || %{})
      |> assign(:recommended_action, recommended)
      |> assign(:wallet_position, wallet_position)
      |> assign(:routing_snapshot, Presenter.routing_snapshot(subject))
      |> assign(:ingress_accounts, ingress_accounts)
      |> assign(
        :subject_heading,
        Presenter.subject_heading(subject, assigns.subject_id, assigns.subject_market)
      )
      |> assign(:subject_summary, Presenter.subject_summary(subject, assigns.subject_market))
      |> assign(:ingress_count, length(ingress_accounts))
      |> assign(:subject_symbol, Presenter.subject_symbol(assigns.subject_market))
      |> assign(:subject_auction_href, Presenter.subject_auction_href(assigns.subject_market))

    ~H"""
    <.shell current_human={@current_human} active_view={@active_view}>
      <.subject_styles />

      <%= if @subject do %>
        <section id="subject-overview" class="al-subject-page">
          <SubjectComponents.header
            subject={@subject}
            subject_id={@subject_id}
            subject_heading={@subject_heading}
            subject_summary={@subject_summary}
            subject_symbol={@subject_symbol}
            subject_auction_href={@subject_auction_href}
            recommended_action={@recommended_action}
          />

          <SubjectComponents.metric_grid wallet_position={@wallet_position} />

          <SubjectComponents.revenue_routing
            routing_snapshot={@routing_snapshot}
            subject={@subject}
          />

          <section class="al-subject-main-grid">
            <div class="al-subject-main-stack">
              <.action_desk
                id="subject-primary-action-desk"
                title={Presenter.recommended_action_heading(@recommended_action)}
                body={Presenter.recommended_action_summary(@recommended_action, @wallet_position)}
                status_label="Review the prepared transaction before signing."
                class="al-subject-action-desk"
              >
                <:primary>
                  <%= case @recommended_action do %>
                    <% :stake -> %>
                      <%= if @pending_actions[:stake] do %>
                        <.wallet_tx_button
                          id="subject-stake-primary"
                          class="al-subject-primary-button"
                          tx_request={@pending_actions[:stake].tx_request}
                          register_endpoint={~p"/v1/app/subjects/#{@subject_id}/stake"}
                          register_body={%{"amount" => @stake_form["amount"]}}
                          pending_message="Stake transaction sent. Waiting for confirmation."
                          success_message="Stake registered."
                        >
                          Send stake transaction
                        </.wallet_tx_button>
                      <% else %>
                        <button
                          type="button"
                          class="al-subject-primary-button"
                          phx-click="prepare_action"
                          phx-value-action="stake"
                        >
                          Prepare stake
                        </button>
                      <% end %>
                    <% :claim -> %>
                      <%= if @pending_actions[:claim] do %>
                        <.wallet_tx_button
                          id="subject-claim-primary"
                          class="al-subject-primary-button"
                          tx_request={@pending_actions[:claim].tx_request}
                          register_endpoint={~p"/v1/app/subjects/#{@subject_id}/claim-usdc"}
                          register_body={%{}}
                          pending_message="Claim transaction sent. Waiting for confirmation."
                          success_message="USDC claim registered."
                        >
                          Send claim transaction
                        </.wallet_tx_button>
                      <% else %>
                        <button
                          type="button"
                          class="al-subject-primary-button"
                          phx-click="prepare_action"
                          phx-value-action="claim"
                        >
                          Prepare USDC claim
                        </button>
                      <% end %>
                    <% :unstake -> %>
                      <%= if @pending_actions[:unstake] do %>
                        <.wallet_tx_button
                          id="subject-unstake-primary"
                          class="al-subject-primary-button"
                          tx_request={@pending_actions[:unstake].tx_request}
                          register_endpoint={~p"/v1/app/subjects/#{@subject_id}/unstake"}
                          register_body={%{"amount" => @unstake_form["amount"]}}
                          pending_message="Unstake transaction sent. Waiting for confirmation."
                          success_message="Unstake registered."
                        >
                          Send unstake transaction
                        </.wallet_tx_button>
                      <% else %>
                        <button
                          type="button"
                          class="al-subject-primary-button"
                          phx-click="prepare_action"
                          phx-value-action="unstake"
                        >
                          Prepare unstake
                        </button>
                      <% end %>
                    <% :claim_and_stake_emissions -> %>
                      <%= if @pending_actions[:claim_and_stake_emissions] do %>
                        <.wallet_tx_button
                          id="subject-claim-and-stake-primary"
                          class="al-subject-primary-button"
                          tx_request={@pending_actions[:claim_and_stake_emissions].tx_request}
                          register_endpoint={~p"/v1/app/subjects/#{@subject_id}/claim-and-stake-emissions"}
                          register_body={%{}}
                          pending_message="Claim and stake sent. Waiting for confirmation."
                          success_message="Emission claim and stake registered."
                        >
                          Send claim and stake
                        </.wallet_tx_button>
                      <% else %>
                        <button
                          type="button"
                          class="al-subject-primary-button"
                          phx-click="prepare_action"
                          phx-value-action="claim_and_stake_emissions"
                        >
                          Prepare claim and stake
                        </button>
                      <% end %>
                    <% _ -> %>
                      <.link navigate={~p"/contracts?subject_id=#{@subject_id}"} class="al-subject-primary-button">
                        Open advanced review
                      </.link>
                  <% end %>
                </:primary>

                <:secondary>
                  <.link navigate={~p"/contracts?subject_id=#{@subject_id}"} class="al-subject-secondary-button">
                    Review contracts
                  </.link>
                </:secondary>

                <:aside>
                  <div class="al-subject-flow-card" aria-hidden="true">
                  <div class="al-subject-flow-box">
                    <span>Your wallet</span>
                    <strong>{@wallet_position.wallet_token_balance}</strong>
                    <p>Available to stake</p>
                  </div>
                  <div class="al-subject-flow-arrow">→</div>
                  <div class="al-subject-flow-box is-featured">
                    <span>Revenue splitter</span>
                    <strong>{@wallet_position.wallet_stake_balance}</strong>
                    <p>Currently staked</p>
                  </div>
                  <div class="al-subject-flow-arrow">→</div>
                  <div class="al-subject-flow-box">
                    <span>Earnings</span>
                    <strong>{@wallet_position.claimable_usdc}</strong>
                    <p>USDC ready now</p>
                  </div>
                </div>
                </:aside>
              </.action_desk>

              <section class="al-subject-action-grid">
                <article class="al-subject-action-card">
                  <div>
                    <p class="al-kicker">Stake</p>
                    <h3>Move wallet tokens into the splitter.</h3>
                    <p>{@wallet_position.stake_note}</p>
                  </div>

                  <form phx-change="stake_changed" class="al-subject-form">
                    <label for="subject-stake-amount">Amount</label>
                    <input
                      id="subject-stake-amount"
                      type="text"
                      inputmode="decimal"
                      name="stake[amount]"
                      value={@stake_form["amount"]}
                      placeholder="0.0"
                    />
                  </form>

                  <div class="al-subject-action-footer">
                    <%= if @pending_actions[:stake] do %>
                      <.wallet_tx_button
                        id="subject-stake"
                        class="al-subject-action-button"
                        tx_request={@pending_actions[:stake].tx_request}
                        register_endpoint={~p"/v1/app/subjects/#{@subject_id}/stake"}
                        register_body={%{"amount" => @stake_form["amount"]}}
                        pending_message="Stake transaction sent. Waiting for confirmation."
                        success_message="Stake registered."
                      >
                        Send stake transaction
                      </.wallet_tx_button>
                    <% else %>
                      <button
                        type="button"
                        class="al-subject-action-button"
                        phx-click="prepare_action"
                        phx-value-action="stake"
                      >
                        Prepare stake
                      </button>
                    <% end %>

                    <span :if={@recommended_action == :stake} class="al-subject-badge">
                      Recommended
                    </span>
                  </div>
                </article>

                <article class="al-subject-action-card">
                  <div>
                    <p class="al-kicker">Claim</p>
                    <h3>Withdraw available USDC to this wallet.</h3>
                    <p>{@wallet_position.claim_note}</p>
                  </div>

                  <div class="al-subject-action-footer">
                    <%= cond do %>
                      <% @recommended_action == :claim -> %>
                        <span class="al-subject-badge">Recommended above</span>
                      <% @pending_actions[:claim] -> %>
                      <.wallet_tx_button
                        id="subject-claim"
                        class="al-subject-action-button"
                        tx_request={@pending_actions[:claim].tx_request}
                        register_endpoint={~p"/v1/app/subjects/#{@subject_id}/claim-usdc"}
                        register_body={%{}}
                        pending_message="Claim transaction sent. Waiting for confirmation."
                        success_message="USDC claim registered."
                      >
                        Send claim transaction
                      </.wallet_tx_button>
                      <% true -> %>
                      <button
                        type="button"
                        class="al-subject-action-button"
                        phx-click="prepare_action"
                        phx-value-action="claim"
                      >
                        Prepare USDC claim
                      </button>
                    <% end %>
                  </div>
                </article>

                <article class="al-subject-secondary-card">
                  <div>
                    <p class="al-kicker">Unstake</p>
                    <h3>Move committed tokens back to the wallet.</h3>
                    <p>{@wallet_position.unstake_note}</p>
                  </div>

                  <form phx-change="unstake_changed" class="al-subject-form">
                    <label for="subject-unstake-amount">Amount</label>
                    <input
                      id="subject-unstake-amount"
                      type="text"
                      inputmode="decimal"
                      name="unstake[amount]"
                      value={@unstake_form["amount"]}
                      placeholder="0.0"
                    />
                  </form>

                  <div class="al-subject-action-footer">
                    <%= if @pending_actions[:unstake] do %>
                      <.wallet_tx_button
                        id="subject-unstake"
                        class="al-subject-ghost-button"
                        tx_request={@pending_actions[:unstake].tx_request}
                        register_endpoint={~p"/v1/app/subjects/#{@subject_id}/unstake"}
                        register_body={%{"amount" => @unstake_form["amount"]}}
                        pending_message="Unstake transaction sent. Waiting for confirmation."
                        success_message="Unstake registered."
                      >
                        Send unstake transaction
                      </.wallet_tx_button>
                    <% else %>
                      <button
                        type="button"
                        class="al-subject-ghost-button"
                        phx-click="prepare_action"
                        phx-value-action="unstake"
                      >
                        Prepare unstake
                      </button>
                    <% end %>
                  </div>
                </article>

                <article class="al-subject-secondary-card">
                  <div>
                    <p class="al-kicker">Emissions</p>
                    <h3>Claim reward tokens or roll them back into stake.</h3>
                    <p>{@wallet_position.emissions_note}</p>
                  </div>

                  <div class="al-subject-split-actions">
                    <%= if @pending_actions[:claim_emissions] do %>
                      <.wallet_tx_button
                        id="subject-claim-emissions"
                        class="al-subject-ghost-button"
                        tx_request={@pending_actions[:claim_emissions].tx_request}
                        register_endpoint={~p"/v1/app/subjects/#{@subject_id}/claim-emissions"}
                        register_body={%{}}
                        pending_message="Emission claim sent. Waiting for confirmation."
                        success_message="Emission claim registered."
                      >
                        Send emissions claim
                      </.wallet_tx_button>
                    <% else %>
                      <button
                        type="button"
                        class="al-subject-ghost-button"
                        phx-click="prepare_action"
                        phx-value-action="claim_emissions"
                      >
                        Prepare emissions claim
                      </button>
                    <% end %>

                    <%= if @pending_actions[:claim_and_stake_emissions] do %>
                      <.wallet_tx_button
                        id="subject-claim-and-stake-emissions"
                        class="al-subject-ghost-button"
                        tx_request={@pending_actions[:claim_and_stake_emissions].tx_request}
                        register_endpoint={~p"/v1/app/subjects/#{@subject_id}/claim-and-stake-emissions"}
                        register_body={%{}}
                        pending_message="Claim and stake sent. Waiting for confirmation."
                        success_message="Emission claim and stake registered."
                      >
                        Send claim and stake
                      </.wallet_tx_button>
                    <% else %>
                      <button
                        type="button"
                        class="al-subject-ghost-button"
                        phx-click="prepare_action"
                        phx-value-action="claim_and_stake_emissions"
                      >
                        Prepare claim and stake
                      </button>
                    <% end %>
                  </div>
                </article>

                <article class="al-subject-secondary-card">
                  <div>
                    <p class="al-kicker">Ingress</p>
                    <h3>Move USDC from intake accounts into revenue.</h3>
                    <p>Known USDC intake accounts: {@ingress_count}. Money here counts after it is swept.</p>
                  </div>

                  <%= if @subject.can_manage_ingress and @ingress_accounts != [] do %>
                    <div class="al-subject-split-actions">
                      <%= for ingress <- @ingress_accounts do %>
                        <%= if @pending_actions[{:sweep, ingress.address}] do %>
                          <.wallet_tx_button
                            id={"subject-sweep-#{ingress.address}"}
                            class="al-subject-ghost-button"
                            tx_request={@pending_actions[{:sweep, ingress.address}].tx_request}
                            register_endpoint={~p"/v1/app/subjects/#{@subject_id}/ingress/#{ingress.address}/sweep"}
                            register_body={%{}}
                            pending_message="Sweep transaction sent. Waiting for confirmation."
                            success_message="Ingress sweep registered."
                          >
                            Send sweep transaction
                          </.wallet_tx_button>
                        <% else %>
                          <button
                            type="button"
                            class="al-subject-ghost-button"
                            phx-click="prepare_action"
                            phx-value-action="sweep"
                            phx-value-address={ingress.address}
                          >
                            Prepare sweep
                          </button>
                        <% end %>
                      <% end %>
                    </div>
                  <% else %>
                    <p class="al-subject-muted-copy">
                      No sweep action is available from this wallet right now.
                    </p>
                  <% end %>
                </article>
              </section>

              <SubjectComponents.advanced_review subject={@subject} subject_id={@subject_id} />
            </div>

            <aside class="al-subject-side-panel">
              <div class="al-subject-side-tabs" role="tablist" aria-label="Subject side tabs">
                <button
                  :for={tab <- Presenter.side_tabs()}
                  type="button"
                  role="tab"
                  aria-selected={@side_tab == tab}
                  class={["al-subject-side-tab", @side_tab == tab && "is-active"]}
                  phx-click="side_tab_changed"
                  phx-value-tab={tab}
                >
                  {Presenter.side_tab_label(tab)}
                </button>
              </div>

              <div :if={@side_tab == "state"} class="al-subject-side-stack">
                <div class="al-subject-state-card">
                  <div class="al-subject-state-head">
                    <span class="al-subject-status">
                      <span class="al-subject-status-dot"></span>
                      <span>{Presenter.recommended_status_label(@recommended_action)}</span>
                    </span>
                    <span>{Map.get(@subject, :chain_label, "Base")}</span>
                  </div>

                  <dl class="al-subject-side-list">
                    <div><dt>Total staked</dt><dd>{@subject.total_staked}</dd></div>
                    <div><dt>Treasury residual</dt><dd>{@subject.treasury_residual_usdc} USDC</dd></div>
                    <div><dt>Protocol reserve</dt><dd>{@subject.protocol_reserve_usdc} USDC</dd></div>
                    <div><dt>Ingress accounts</dt><dd>{@ingress_count}</dd></div>
                  </dl>
                </div>

                <div class="al-subject-state-card">
                  <p class="al-kicker">Wallet view</p>
                  <dl class="al-subject-side-list">
                    <div><dt>Claimable now</dt><dd>{@wallet_position.claimable_usdc} USDC</dd></div>
                    <div><dt>Available to stake</dt><dd>{@wallet_position.wallet_token_balance}</dd></div>
                    <div><dt>Committed</dt><dd>{@wallet_position.wallet_stake_balance}</dd></div>
                    <div><dt>Emissions</dt><dd>{@wallet_position.claimable_stake_token}</dd></div>
                  </dl>
                </div>
              </div>

              <div :if={@side_tab == "balances"} class="al-subject-side-stack">
                <div class="al-subject-state-card">
                  <p class="al-kicker">Wallet balances</p>
                  <dl class="al-subject-side-list">
                    <div><dt>Claimable USDC</dt><dd>{@wallet_position.claimable_usdc}</dd></div>
                    <div><dt>Wallet token balance</dt><dd>{@wallet_position.wallet_token_balance}</dd></div>
                    <div><dt>Your staked tokens</dt><dd>{@wallet_position.wallet_stake_balance}</dd></div>
                    <div><dt>Claimable emissions</dt><dd>{@wallet_position.claimable_stake_token}</dd></div>
                  </dl>
                </div>

                <div class="al-subject-state-card">
                  <p class="al-kicker">Protocol balances</p>
                  <dl class="al-subject-side-list">
                    <div><dt>Total staked</dt><dd>{@subject.total_staked}</dd></div>
                    <div><dt>Treasury residual</dt><dd>{@subject.treasury_residual_usdc}</dd></div>
                    <div><dt>Protocol reserve</dt><dd>{@subject.protocol_reserve_usdc}</dd></div>
                    <div><dt>Undistributed dust</dt><dd>{Map.get(@subject, :undistributed_dust_usdc, "0")}</dd></div>
                  </dl>
                </div>
              </div>

              <div :if={@side_tab == "addresses"} class="al-subject-side-stack">
                <div class="al-subject-state-card">
                  <p class="al-kicker">Addresses</p>
                  <div class="al-subject-address-list">
                    <article>
                      <span>Subject id</span>
                      <code>{@subject.subject_id}</code>
                    </article>
                    <article>
                      <span>Token</span>
                      <code>{@subject.token_address}</code>
                    </article>
                    <article>
                      <span>Splitter</span>
                      <code>{@subject.splitter_address}</code>
                    </article>
                    <article>
                      <span>Default ingress</span>
                      <code>{@subject.default_ingress_address}</code>
                    </article>
                  </div>
                </div>

                <div class="al-subject-state-card">
                  <p class="al-kicker">Known USDC intake accounts</p>
                  <%= if @ingress_accounts == [] do %>
                    <p class="al-subject-muted-copy">
                      No ingress accounts are currently available for this subject.
                    </p>
                  <% else %>
                    <div class="al-subject-address-list">
                      <article :for={ingress <- @ingress_accounts}>
                        <span>
                          {if ingress.is_default, do: "Default ingress", else: "Ingress account"}
                        </span>
                        <code>{ingress.address}</code>
                        <strong>{ingress.usdc_balance} USDC</strong>
                      </article>
                    </div>
                  <% end %>
                </div>
              </div>
            </aside>
          </section>
        </section>
      <% else %>
        <.empty_state
          title="Subject state is unavailable."
          body="Check that the launch finished successfully and that this subject id exists in the current launch stack."
          mark="SU"
          action_label="Back to auctions"
          action_href={~p"/auctions"}
        />
      <% end %>

      <.flash_group flash={@flash} />
    </.shell>
    """
  end

  defp subject_styles(assigns) do
    ~H"""
    <style>
      #subject-overview.al-subject-page {
        display: grid;
        gap: clamp(1rem, 2vw, 1.5rem);
      }

      .al-subject-header,
      .al-subject-metric-card,
      .al-routing-policy-panel,
      .al-routing-history-panel,
      .al-routing-ledger-card,
      .al-subject-action-card,
      .al-subject-secondary-card,
      .al-subject-side-panel,
      .al-subject-review-panel,
      .al-subject-state-card {
        border: 1px solid color-mix(in srgb, var(--al-border) 88%, white 12%);
        background: color-mix(in srgb, var(--al-panel-strong) 92%, white 8%);
        box-shadow: 0 20px 60px -48px rgba(17, 35, 64, 0.28);
      }

      .al-subject-header {
        border-radius: 1.6rem;
        padding: clamp(1.1rem, 2.4vw, 1.6rem);
        display: flex;
        justify-content: space-between;
        gap: 1.25rem;
        align-items: flex-start;
      }

      .al-subject-title-group,
      .al-subject-heading-block,
      .al-subject-main-stack,
      .al-subject-side-stack {
        display: grid;
        gap: 0.85rem;
      }

      .al-subject-back {
        display: inline-flex;
        align-items: center;
        gap: 0.45rem;
        color: var(--al-muted);
        text-decoration: none;
      }

      .al-subject-title-row {
        display: flex;
        gap: 1rem;
        align-items: flex-start;
      }

      .al-subject-mark {
        width: clamp(4.5rem, 7vw, 5.8rem);
        aspect-ratio: 1;
        border-radius: 1.5rem;
        display: grid;
        place-items: center;
        background:
          radial-gradient(circle at 30% 30%, rgba(72, 123, 255, 0.28), transparent 48%),
          linear-gradient(180deg, rgba(10, 31, 78, 0.98), rgba(15, 48, 108, 0.92));
        color: white;
        font-family: var(--al-font-display);
        font-size: clamp(1.1rem, 2vw, 1.5rem);
        letter-spacing: 0.14em;
      }

      .al-subject-heading-line {
        display: flex;
        flex-wrap: wrap;
        gap: 0.65rem;
        align-items: center;
      }

      .al-subject-heading-line h1 {
        margin: 0;
        font-size: clamp(2rem, 5vw, 3.4rem);
        line-height: 0.94;
      }

      .al-subject-chip,
      .al-subject-badge {
        display: inline-flex;
        align-items: center;
        gap: 0.35rem;
        border-radius: 999px;
        padding: 0.25rem 0.6rem;
        background: rgba(36, 94, 255, 0.08);
        color: color-mix(in srgb, var(--brand-primary) 78%, var(--al-text) 22%);
        font-size: 0.76rem;
      }

      .al-subject-meta,
      .al-subject-header-actions,
      .al-subject-hero-actions,
      .al-subject-action-footer,
      .al-subject-review-actions,
      .al-subject-split-actions {
        display: flex;
        flex-wrap: wrap;
        gap: 0.75rem;
        align-items: center;
      }

      .al-subject-meta {
        color: var(--al-muted);
      }

      .al-subject-status {
        display: inline-flex;
        align-items: center;
        gap: 0.4rem;
      }

      .al-subject-status-dot {
        width: 0.55rem;
        height: 0.55rem;
        border-radius: 999px;
        background: #16a34a;
        box-shadow: 0 0 0 0.18rem rgba(22, 163, 74, 0.12);
      }

      .al-subject-summary,
      .al-subject-muted-copy,
      .al-subject-review-card p {
        margin: 0;
        color: var(--al-muted);
        line-height: 1.6;
      }

      .al-subject-primary-button,
      .al-subject-secondary-button,
      .al-subject-action-button,
      .al-subject-ghost-button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 2.8rem;
        border-radius: 0.95rem;
        padding: 0.78rem 1.1rem;
        text-decoration: none;
        transition: transform 160ms ease, box-shadow 160ms ease, border-color 160ms ease;
      }

      .al-subject-primary-button,
      .al-subject-action-button {
        border: 1px solid color-mix(in srgb, var(--brand-primary) 78%, white 22%);
        background: color-mix(in srgb, var(--brand-primary) 86%, white 14%);
        color: white;
        box-shadow: 0 18px 36px -26px color-mix(in srgb, var(--brand-primary) 68%, black 32%);
      }

      .al-subject-secondary-button,
      .al-subject-ghost-button {
        border: 1px solid color-mix(in srgb, var(--al-border) 82%, white 18%);
        background: transparent;
        color: var(--al-text);
      }

      .al-subject-primary-button:hover,
      .al-subject-secondary-button:hover,
      .al-subject-action-button:hover,
      .al-subject-ghost-button:hover {
        transform: translateY(-1px);
      }

      .al-subject-metric-grid,
      .al-subject-review-grid {
        display: grid;
        gap: 1rem;
        grid-template-columns: repeat(4, minmax(0, 1fr));
      }

      .al-routing-policy-panel {
        border-radius: 1.55rem;
        padding: clamp(1.1rem, 2.3vw, 1.5rem);
        display: grid;
        gap: 1rem;
        grid-template-columns: minmax(0, 1.15fr) minmax(0, 1fr);
        align-items: start;
      }

      .al-routing-policy-copy,
      .al-routing-policy-stats,
      .al-routing-ledger,
      .al-routing-history-list {
        display: grid;
        gap: 0.9rem;
      }

      .al-routing-policy-copy h2,
      .al-routing-history-head h3 {
        margin: 0;
        font-size: clamp(1.4rem, 3vw, 2rem);
        line-height: 1.02;
      }

      .al-routing-policy-copy > p {
        margin: 0;
        color: var(--al-muted);
        line-height: 1.7;
      }

      .al-routing-policy-stats {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .al-routing-change-visual {
        border-radius: 1.25rem;
        padding: 1rem;
        background:
          linear-gradient(180deg, rgba(8, 31, 74, 0.04), rgba(8, 31, 74, 0)),
          color-mix(in srgb, white 90%, var(--al-panel) 10%);
        display: grid;
        gap: 0.9rem;
      }

      .al-routing-change-copy,
      .al-routing-change-chart {
        display: grid;
        gap: 0.75rem;
      }

      .al-routing-change-copy {
        grid-template-columns: minmax(0, 0.95fr) minmax(0, 1.05fr);
        align-items: end;
      }

      .al-routing-change-copy span {
        display: inline-flex;
        color: var(--al-muted);
        font-size: 0.78rem;
      }

      .al-routing-change-copy strong {
        display: block;
        margin-top: 0.15rem;
        font-family: var(--al-font-display);
        font-size: clamp(1.05rem, 2vw, 1.4rem);
        line-height: 1.04;
      }

      .al-routing-change-copy p {
        margin: 0;
        color: var(--al-muted);
        line-height: 1.6;
      }

      .al-routing-change-chart {
        grid-template-columns: minmax(5.8rem, 0.55fr) minmax(0, 1fr) minmax(5.8rem, 0.55fr);
        align-items: end;
      }

      .al-routing-change-chart svg {
        width: 100%;
        height: auto;
        overflow: visible;
      }

      .al-routing-change-axis {
        stroke: color-mix(in srgb, var(--al-border) 72%, white 28%);
        stroke-width: 1.5;
        stroke-linecap: round;
      }

      .al-routing-change-line {
        fill: none;
        stroke: color-mix(in srgb, var(--brand-primary) 78%, #1d4ed8 22%);
        stroke-width: 3;
        stroke-linecap: round;
        stroke-linejoin: round;
      }

      .al-routing-change-dot {
        stroke: white;
        stroke-width: 3;
      }

      .al-routing-change-dot.is-current {
        fill: color-mix(in srgb, var(--brand-primary) 82%, white 18%);
      }

      .al-routing-change-dot.is-next {
        fill: color-mix(in srgb, #16a34a 78%, white 22%);
      }

      .al-routing-change-rate {
        fill: color-mix(in srgb, var(--al-text) 92%, var(--brand-primary) 8%);
        font-family: var(--al-font-display);
        font-size: 0.9rem;
        letter-spacing: 0.02em;
      }

      .al-routing-change-point {
        display: grid;
        gap: 0.25rem;
        color: var(--al-muted);
      }

      .al-routing-change-point strong {
        color: var(--al-text);
        font-family: var(--al-font-display);
        font-size: 1.1rem;
        line-height: 1;
      }

      .al-routing-change-point.is-next {
        text-align: right;
      }

      .al-routing-policy-stats article,
      .al-routing-ledger-card,
      .al-routing-history-item {
        border-radius: 1.2rem;
        padding: 1rem;
        background: color-mix(in srgb, white 88%, var(--al-panel) 12%);
        display: grid;
        gap: 0.3rem;
      }

      .al-routing-policy-stats span,
      .al-routing-ledger-card span,
      .al-routing-history-item span,
      .al-routing-policy-stats p,
      .al-routing-ledger-card p,
      .al-routing-history-item p {
        margin: 0;
        color: var(--al-muted);
      }

      .al-routing-policy-stats strong,
      .al-routing-ledger-card strong {
        font-family: var(--al-font-display);
        font-size: clamp(1.15rem, 2vw, 1.55rem);
        line-height: 0.98;
      }

      .al-routing-ledger {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .al-routing-ledger-card {
        min-height: 100%;
      }

      .al-routing-history-panel {
        border-radius: 1.45rem;
        padding: 1rem 1.15rem;
        display: grid;
        gap: 1rem;
      }

      .al-routing-history-head {
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        gap: 1rem;
      }

      .al-routing-history-head > span {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-width: 2.8rem;
        min-height: 2.8rem;
        border-radius: 999px;
        background: color-mix(in srgb, var(--brand-primary) 12%, white 88%);
        color: color-mix(in srgb, var(--brand-primary) 72%, var(--al-text) 28%);
        font-family: var(--al-font-display);
      }

      .al-routing-history-list {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }

      .al-routing-history-meta {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.6rem;
      }

      .al-routing-history-pill {
        display: inline-flex;
        align-items: center;
        min-height: 1.8rem;
        padding: 0.2rem 0.55rem;
        border-radius: 999px;
        background: rgba(36, 94, 255, 0.08);
        color: color-mix(in srgb, var(--brand-primary) 78%, var(--al-text) 22%);
        font-size: 0.74rem;
      }

      .al-subject-metric-card {
        border-radius: 1.35rem;
        padding: 1.15rem;
        display: grid;
        gap: 0.35rem;
      }

      .al-subject-metric-card p,
      .al-subject-metric-card span,
      .al-subject-review-card span,
      .al-subject-side-list dt,
      .al-subject-address-list span,
      .al-subject-address-list strong {
        color: var(--al-muted);
      }

      .al-subject-metric-card strong {
        font-family: var(--al-font-display);
        font-size: clamp(1.45rem, 2.5vw, 2rem);
        letter-spacing: 0.02em;
      }

      .al-subject-main-grid {
        display: grid;
        gap: 1rem;
        grid-template-columns: minmax(0, 1.7fr) minmax(18rem, 0.9fr);
        align-items: start;
      }

      .al-subject-hero-panel {
        position: relative;
        overflow: hidden;
        border-radius: 1.7rem;
        padding: clamp(1.25rem, 2.7vw, 1.8rem);
        display: grid;
        gap: 1rem;
        grid-template-columns: minmax(0, 1.15fr) minmax(16rem, 0.9fr);
        background:
          radial-gradient(circle at 82% 28%, rgba(53, 131, 255, 0.35), transparent 24%),
          radial-gradient(circle at 75% 78%, rgba(77, 120, 255, 0.18), transparent 28%),
          linear-gradient(180deg, rgba(8, 31, 74, 0.98), rgba(10, 25, 56, 0.98));
        color: white;
      }

      .al-subject-hero-panel::after {
        content: "";
        position: absolute;
        inset: auto -6% -30% 28%;
        height: 14rem;
        background:
          radial-gradient(circle at 20% 40%, rgba(90, 181, 255, 0.34), transparent 30%),
          repeating-radial-gradient(circle at center, rgba(255, 255, 255, 0.1) 0 1px, transparent 1px 12px);
        opacity: 0.3;
        pointer-events: none;
      }

      .al-subject-hero-copy,
      .al-subject-flow-card {
        position: relative;
        z-index: 1;
      }

      .al-subject-hero-copy h2 {
        margin: 0;
        font-size: clamp(2rem, 4.6vw, 3.4rem);
        line-height: 0.94;
      }

      .al-subject-hero-copy p {
        margin: 0;
        color: rgba(238, 245, 255, 0.8);
        line-height: 1.7;
      }

      .al-subject-footnote {
        color: rgba(238, 245, 255, 0.72);
        font-size: 0.92rem;
      }

      .al-subject-flow-card {
        display: grid;
        align-content: center;
        gap: 0.75rem;
      }

      .al-subject-flow-box {
        border-radius: 1.25rem;
        border: 1px solid rgba(167, 198, 255, 0.22);
        background: rgba(255, 255, 255, 0.06);
        padding: 1rem;
        display: grid;
        gap: 0.35rem;
        text-align: center;
      }

      .al-subject-flow-box span,
      .al-subject-flow-box p {
        margin: 0;
        color: rgba(238, 245, 255, 0.72);
      }

      .al-subject-flow-box strong {
        font-family: var(--al-font-display);
        font-size: 1.5rem;
      }

      .al-subject-flow-box.is-featured {
        background:
          linear-gradient(180deg, rgba(52, 126, 255, 0.34), rgba(34, 84, 206, 0.18)),
          rgba(255, 255, 255, 0.08);
        box-shadow:
          0 0 0 1px rgba(119, 177, 255, 0.18),
          0 0 36px -16px rgba(52, 126, 255, 0.8);
      }

      .al-subject-flow-arrow {
        justify-self: center;
        font-size: 1.6rem;
        color: rgba(238, 245, 255, 0.76);
      }

      .al-subject-action-grid {
        display: grid;
        gap: 1rem;
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .al-subject-action-card,
      .al-subject-secondary-card {
        border-radius: 1.45rem;
        padding: 1.15rem;
        display: grid;
        gap: 0.85rem;
      }

      .al-subject-action-card h3,
      .al-subject-secondary-card h3,
      .al-subject-review-panel h3 {
        margin: 0;
        font-size: 1.25rem;
      }

      .al-subject-action-card p:not(.al-kicker),
      .al-subject-secondary-card p:not(.al-kicker) {
        margin: 0;
        color: var(--al-muted);
      }

      .al-subject-form {
        display: grid;
        gap: 0.45rem;
      }

      .al-subject-form label {
        color: var(--al-muted);
        font-size: 0.85rem;
      }

      .al-subject-form input {
        width: 100%;
        min-height: 2.9rem;
        border-radius: 0.9rem;
        border: 1px solid color-mix(in srgb, var(--al-border) 88%, white 12%);
        background: color-mix(in srgb, white 90%, var(--al-panel) 10%);
        padding: 0 0.9rem;
        color: var(--al-text);
      }

      .al-subject-review-panel {
        border-radius: 1.45rem;
        padding: 1rem 1.15rem 1.15rem;
      }

      .al-subject-review-panel summary {
        list-style: none;
        display: flex;
        justify-content: space-between;
        align-items: center;
        cursor: pointer;
      }

      .al-subject-review-panel summary::-webkit-details-marker {
        display: none;
      }

      .al-subject-review-grid {
        margin-top: 1rem;
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }

      .al-subject-review-card {
        border-radius: 1.2rem;
        padding: 1rem;
        background: color-mix(in srgb, white 86%, var(--al-panel) 14%);
        display: grid;
        gap: 0.4rem;
      }

      .al-subject-review-card strong {
        font-size: 1.1rem;
      }

      .al-subject-side-panel {
        border-radius: 1.5rem;
        padding: 1rem;
        display: grid;
        gap: 0.9rem;
      }

      .al-subject-side-tabs {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 0.5rem;
        padding: 0.3rem;
        border-radius: 1rem;
        background: color-mix(in srgb, var(--al-panel) 84%, white 16%);
      }

      .al-subject-side-tab {
        min-height: 2.5rem;
        border-radius: 0.8rem;
        border: none;
        background: transparent;
        color: var(--al-muted);
      }

      .al-subject-side-tab.is-active {
        background: color-mix(in srgb, var(--brand-primary) 12%, white 88%);
        color: color-mix(in srgb, var(--brand-primary) 74%, var(--al-text) 26%);
      }

      .al-subject-state-card {
        border-radius: 1.2rem;
        padding: 1rem;
        display: grid;
        gap: 0.85rem;
      }

      .al-subject-state-head {
        display: flex;
        justify-content: space-between;
        gap: 0.75rem;
        color: var(--al-muted);
      }

      .al-subject-side-list,
      .al-subject-address-list {
        display: grid;
        gap: 0.75rem;
      }

      .al-subject-side-list div,
      .al-subject-address-list article {
        display: grid;
        gap: 0.25rem;
        padding-bottom: 0.75rem;
        border-bottom: 1px solid color-mix(in srgb, var(--al-border) 72%, transparent);
      }

      .al-subject-side-list div:last-child,
      .al-subject-address-list article:last-child {
        border-bottom: none;
        padding-bottom: 0;
      }

      .al-subject-side-list dd {
        margin: 0;
        font-size: 1.05rem;
      }

      .al-subject-address-list code {
        overflow-wrap: anywhere;
        font-size: 0.82rem;
        color: var(--al-text);
      }

      @media (max-width: 1120px) {
        .al-subject-main-grid,
        .al-subject-hero-panel,
        .al-routing-policy-panel,
        .al-subject-metric-grid,
        .al-subject-review-grid,
        .al-routing-history-list {
          grid-template-columns: 1fr;
        }

        .al-subject-action-grid {
          grid-template-columns: 1fr;
        }

        .al-routing-policy-stats,
        .al-routing-ledger,
        .al-routing-change-copy,
        .al-routing-change-chart {
          grid-template-columns: 1fr;
        }

        .al-routing-change-point.is-next {
          text-align: left;
        }
      }

      @media (max-width: 760px) {
        .al-subject-header,
        .al-subject-title-row {
          flex-direction: column;
        }

        .al-subject-side-tabs {
          grid-template-columns: 1fr;
        }
      }
    </style>
    """
  end

  defp assign_subject(socket, subject_id) do
    case context_module().get_subject(subject_id, socket.assigns[:current_human]) do
      {:ok, subject} -> assign(socket, :subject, subject)
      _ -> assign(socket, :subject, nil)
    end
  end

  defp reload_subject(socket) do
    socket
    |> assign(:pending_actions, %{})
    |> assign(:subject_market, load_subject_market(socket.assigns.subject_id))
    |> assign_subject(socket.assigns.subject_id)
  end

  defp prepare_action(socket, action, attrs) do
    subject_id = socket.assigns.subject_id
    current_human = socket.assigns.current_human

    result =
      case action do
        :stake ->
          context_module().stake(subject_id, attrs, current_human)

        :unstake ->
          context_module().unstake(subject_id, attrs, current_human)

        :claim ->
          context_module().claim_usdc(subject_id, attrs, current_human)

        :claim_emissions ->
          context_module().claim_emissions(subject_id, attrs, current_human)

        :claim_and_stake_emissions ->
          context_module().claim_and_stake_emissions(subject_id, attrs, current_human)

        {:sweep, ingress_address} ->
          context_module().sweep_ingress(subject_id, ingress_address, attrs, current_human)
      end

    case result do
      {:ok, %{tx_request: tx_request, subject: subject}} ->
        socket
        |> assign(:subject, subject)
        |> put_pending_action(action, tx_request)

      {:error, reason} ->
        put_flash(socket, :error, Presenter.action_error(reason))
    end
  end

  defp put_pending_action(socket, action, tx_request) do
    assign(
      socket,
      :pending_actions,
      Map.put(socket.assigns.pending_actions, action, %{tx_request: tx_request})
    )
  end

  defp context_module do
    :autolaunch
    |> Application.get_env(:revenue_live, [])
    |> Keyword.get(:context_module, Autolaunch.Revenue)
  end

  defp load_subject_market(subject_id) do
    launch_module().list_auctions(%{"mode" => "all", "sort" => "newest"}, nil)
    |> Enum.find(fn row -> row.subject_id == subject_id end)
  rescue
    _ -> nil
  end

  defp launch_module do
    :autolaunch
    |> Application.get_env(:subject_live, [])
    |> Keyword.get(:launch_module, Launch)
  end
end
