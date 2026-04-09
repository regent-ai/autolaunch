defmodule AutolaunchWeb.LaunchLive do
  use AutolaunchWeb, :live_view

  @cli_command "regent autolaunch prelaunch wizard"
  @launch_inputs [
    %{
      title: "Identity",
      value: "Agent id and linked operator wallet",
      body:
        "Use the wallet that actually controls the ERC-8004 identity. Launch still signs through SIWA."
    },
    %{
      title: "Token basics",
      value: "Name, symbol, and minimum USDC raise",
      body:
        "The minimum raise is now a first-class launch setting. If the auction misses it, bidders can return their USDC."
    },
    %{
      title: "Treasury routing",
      value: "One Agent Safe for treasury, vesting, and contract ownership",
      body:
        "This Safe is part of the signed launch configuration, so confirm it carefully before you run the launch."
    },
    %{
      title: "Hosted metadata",
      value: "Title, description, and image",
      body:
        "The CLI wizard can upload the image and save the hosted launch metadata before publish and launch."
    }
  ]
  @launch_flow [
    %{index: 1, label: "Save plan"},
    %{index: 2, label: "Validate"},
    %{index: 3, label: "Publish"},
    %{index: 4, label: "Run"},
    %{index: 5, label: "Monitor"},
    %{index: 6, label: "Finalize"}
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Launch")
     |> assign(:active_view, "launch")
     |> assign(:cli_command, @cli_command)
     |> assign(:launch_inputs, @launch_inputs)
     |> assign(:launch_flow, @launch_flow)}
  end

  def render(assigns) do
    ~H"""
    <.shell current_human={@current_human} active_view={@active_view}>
      <section id="launch-cli-hero" class="al-hero al-launch-hero al-panel" phx-hook="MissionMotion">
        <div class="al-launch-copy">
          <p class="al-kicker">CLI-first launch</p>
          <h2>Run the launch from the CLI. Use the site to review what happens next.</h2>
          <p class="al-subcopy">
            One plan file feeds validation, publish, launch, monitor, and finalize. The browser
            stays focused on auctions, token holders, and contract reads after the launch is live.
          </p>

          <div class="al-hero-actions">
            <.link navigate={~p"/launch-via-agent"} class="al-cta-link al-cta-link--primary">
              Launch via agent
            </.link>
            <.link navigate={~p"/auctions"} class="al-ghost">Browse auctions</.link>
          </div>

          <div class="al-launch-tags" aria-label="Launch summary">
            <span class="al-launch-tag">One saved plan</span>
            <span class="al-launch-tag">Ethereum Sepolia only</span>
            <span class="al-launch-tag">Browser for review only</span>
          </div>
        </div>

        <.terminal_command_panel
          kicker="Start here"
          title="Starter command"
          command={@cli_command}
          output_label="What happens next"
          output={launch_transcript()}
        />
      </section>

      <section id="launch-cli-steps" class="al-detail-layout" phx-hook="MissionMotion">
        <article id="launch-cli-inputs" class="al-panel al-card" phx-hook="MissionMotion">
          <div class="al-section-head">
            <div>
              <p class="al-kicker">What this does</p>
              <h3>One repeatable operator path</h3>
            </div>
          </div>

          <div class="al-note-grid">
            <article class="al-note-card">
              <span>Save once</span>
              <strong>Capture the full launch plan in the CLI.</strong>
              <p>Keep the operator wallet, Agent Safe, and metadata in one reviewed plan.</p>
            </article>

            <article class="al-note-card">
              <span>Validate once</span>
              <strong>Check the plan before you publish or deploy.</strong>
              <p>Minimum raise, routing, and launch settings are reviewed before chain actions start.</p>
            </article>

            <article class="al-note-card">
              <span>Run once</span>
              <strong>Launch, monitor, and finalize from the same thread of work.</strong>
              <p>The web app picks up after launch for bidding, claims, staking, and revenue reads.</p>
            </article>
          </div>
        </article>

        <article id="launch-cli-needs" class="al-panel al-card" phx-hook="MissionMotion">
          <div class="al-section-head">
            <div>
              <p class="al-kicker">What you need</p>
              <h3>Review these before you start</h3>
            </div>
          </div>

          <div class="al-review-grid">
            <article :for={item <- @launch_inputs} class="al-review-card">
              <span>{item.title}</span>
              <strong>{item.value}</strong>
              <p>{item.body}</p>
            </article>
          </div>
        </article>

        <article id="launch-cli-flow" class="al-panel al-card" phx-hook="MissionMotion">
          <div class="al-section-head">
            <div>
              <p class="al-kicker">What to run</p>
              <h3>The exact sequence</h3>
            </div>
          </div>

          <div class="al-step-row" aria-label="Launch phases">
            <.step_chip :for={step <- @launch_flow} index={step.index} label={step.label} />
          </div>

          <div class="al-compact-list">
            <p><code>regent autolaunch prelaunch wizard</code></p>
            <p><code>regent autolaunch prelaunch validate --plan &lt;plan-id&gt;</code></p>
            <p><code>regent autolaunch prelaunch publish --plan &lt;plan-id&gt;</code></p>
            <p><code>regent autolaunch launch run --plan &lt;plan-id&gt; --watch</code></p>
            <p><code>regent autolaunch launch monitor --job &lt;job-id&gt; --watch</code></p>
            <p><code>regent autolaunch launch finalize --job &lt;job-id&gt; --submit</code></p>
          </div>

          <p class="al-inline-note">
            The backend worker still executes the Foundry deploy. The CLI just keeps the operator
            review path consistent from start to finish.
          </p>
        </article>
      </section>

      <section id="launch-cli-browser-role" class="al-panel al-directory-facts" phx-hook="MissionMotion">
        <div class="al-section-head">
          <div>
            <p class="al-kicker">What stays in the browser</p>
            <h3>Come back here after the launch is live</h3>
          </div>
        </div>

        <div class="al-directory-facts-grid">
          <article class="al-directory-fact-card">
            <span>Auctions</span>
            <strong>Track the live sale, update bids, and inspect returns.</strong>
            <p>Once the token is live, bidders should use the browser instead of the CLI.</p>
          </article>

          <article class="al-directory-fact-card">
            <span>Token holder actions</span>
            <strong>Claim, stake, unstake, and sweep from the token page.</strong>
            <p>Revenue management stays visible to token holders without reopening the launch flow.</p>
          </article>

          <article class="al-directory-fact-card">
            <span>Contract reads</span>
            <strong>Use the advanced console when you need prepared calldata or stack inspection.</strong>
            <p>The contract view stays available, but it is no longer the first operator stop.</p>
          </article>
        </div>

        <div class="al-action-row">
          <.link navigate={~p"/launch-via-agent"} class="al-submit">How to use agents</.link>
          <.link navigate={~p"/auctions"} class="al-ghost">Browse active auctions</.link>
          <.link navigate={~p"/contracts"} class="al-ghost">Open contract console</.link>
        </div>
      </section>

      <.flash_group flash={@flash} />
    </.shell>
    """
  end

  defp launch_transcript do
    """
    > regent autolaunch prelaunch validate --plan plan_alpha
    > regent autolaunch prelaunch publish --plan plan_alpha
    > regent autolaunch launch run --plan plan_alpha --watch
    > regent autolaunch launch monitor --job job_alpha --watch
    > regent autolaunch launch finalize --job job_alpha --submit
    """
    |> String.trim()
  end
end
