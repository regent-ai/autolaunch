defmodule AutolaunchWeb.LaunchViaAgentLive do
  use AutolaunchWeb, :live_view

  alias AutolaunchWeb.LaunchLive.Presenter

  @operator_guides [
    %{
      eyebrow: "OpenClaw",
      title: "Give OpenClaw the whole launch run.",
      body:
        "Start with the wizard, let it gather what is missing, save the plan, and carry the launch through monitoring.",
      copy_label: "Copy OpenClaw brief",
      prompt: """
      Use Autolaunch to prepare and run a token launch for me.

      Start with `regent autolaunch prelaunch wizard`.
      Ask me for any missing launch details before you continue.
      Save the plan, validate it, publish it, run the launch, and monitor the auction.
      Stop for confirmation before every signing step and explain what happens next in plain English.
      """
    },
    %{
      eyebrow: "Hermes",
      title: "Give Hermes the operator checklist.",
      body:
        "Use Hermes when you want a steadier back-and-forth: one saved plan, one launch run, and clear checkpoints along the way.",
      copy_label: "Copy Hermes brief",
      prompt: """
      Help me launch through Autolaunch as an operator.

      Begin with `regent autolaunch prelaunch wizard`.
      Keep the saved plan as the source of truth.
      Walk me through validate, publish, launch, and monitor in order.
      Before each signing step, tell me what it will do and what to check after it lands.
      """
    }
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Launch Via Agent")
     |> assign(:active_view, "launch")
     |> assign(:golden_path, Presenter.launch_via_agent_path())
     |> assign(:operator_guides, @operator_guides)
     |> assign(:launch_command, Presenter.launch_command())
     |> assign(:launch_transcript, Presenter.launch_agent_transcript())}
  end

  def render(assigns) do
    ~H"""
    <.shell current_human={@current_human} active_view={@active_view}>
      <section
        id="launch-via-agent-hero"
        class="al-hero al-launch-hero al-panel"
        phx-hook="MissionMotion"
      >
        <div class="al-launch-copy">
          <p class="al-kicker">Operator path</p>
          <h2>Choose the agent handoff, then move into the main launch console.</h2>
          <p class="al-subcopy">
            This page is the doorway for operator materials. Copy the prompt that fits your agent,
            then keep the real launch path in the launch console and the command line.
          </p>

          <div class="al-hero-actions">
            <.link navigate={~p"/launch"} class="al-cta-link al-cta-link--primary">
              Open launch console
            </.link>
            <button type="button" class="al-ghost" data-copy-value={@launch_command}>
              Copy wizard command
            </button>
          </div>

          <div class="al-launch-tags" aria-label="Launch via agent facts">
            <span class="al-launch-tag">Operator briefs</span>
            <span class="al-launch-tag">CLI-first path</span>
            <span class="al-launch-tag">One saved plan</span>
          </div>

          <div class="al-stat-grid al-launch-stats">
            <.stat_card title="Start here" value="Pick the agent handoff" hint="Copy the brief that matches the operator" />
            <.stat_card title="Main path" value="Open launch console" hint="Use the main launch page for the full sequence" />
            <.stat_card title="Market follow-up" value="Auctions and tokens" hint="Come back to the site once the sale is live" />
          </div>
        </div>

        <.terminal_command_panel
          kicker="Copy and paste"
          title="Starter command"
          command={@launch_command}
          output_label="Golden path"
          output={@launch_transcript}
        />
      </section>

      <section
        id="launch-via-agent-briefs"
        class="al-panel al-home-operator-briefs"
        phx-hook="MissionMotion"
      >
        <div class="al-section-head">
          <div>
            <p class="al-kicker">Choose the operator</p>
            <h3>Pick the agent that should carry the run.</h3>
          </div>
        </div>

        <div class="al-home-brief-grid">
          <article :for={guide <- @operator_guides} class="al-home-brief-card">
            <p class="al-kicker">{guide.eyebrow}</p>
            <h3>{guide.title}</h3>
            <p>{guide.body}</p>

            <div class="al-choice-actions">
              <button type="button" class="al-submit" data-copy-value={guide.prompt}>
                {guide.copy_label}
              </button>
            </div>
          </article>
        </div>
      </section>

      <section
        id="launch-via-agent-path"
        class="al-launch-onboard al-panel"
        phx-hook="MissionMotion"
        aria-label="Launch via agent path"
      >
        <div class="al-onboard-summary">
          <p class="al-kicker">How to use agents</p>
          <h3>Keep the run boring in the best way.</h3>
          <p class="al-subcopy">
            The ideal operator flow is one saved plan, one clear launch run, one monitoring pass,
            and one finish step. Use this page for the handoff and the main launch page for the
            exact sequence.
          </p>
        </div>

        <div class="al-onboard-grid">
          <article :for={item <- @golden_path} class="al-onboard-card">
            <p class="al-onboard-mark">{item.step}</p>
            <strong>{item.title}</strong>
            <p>{item.body}</p>
          </article>
        </div>

        <div class="al-action-row">
          <.link navigate={~p"/launch"} class="al-submit">Open launch console</.link>
          <.link navigate={~p"/agentbook"} class="al-ghost">Trust check</.link>
          <.link navigate={~p"/ens-link"} class="al-ghost">ENS link</.link>
        </div>
      </section>
    </.shell>
    """
  end
end
