defmodule AutolaunchWeb.LaunchViaAgentLive do
  use AutolaunchWeb, :live_view

  alias AutolaunchWeb.LaunchLive.Presenter

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Launch Via Agent")
     |> assign(:active_view, "launch")
     |> assign(:golden_path, Presenter.launch_via_agent_path())
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
          <p class="al-kicker">Launch via agent</p>
          <h2>Launch a token through your OpenClaw or Hermes Agent.</h2>
          <p class="al-subcopy">
            This path is meant to feel operationally simple. Configure the launch in the CLI, keep
            the plan as the source of truth, run the launch, monitor the three-day auction, then
            finalize the post-auction steps.
          </p>

          <div class="al-hero-actions">
            <button
              type="button"
              class="al-cta-link al-cta-link--primary"
              data-copy-value={@launch_command}
            >
              Copy CLI command
            </button>
            <.link navigate={~p"/launch"} class="al-ghost">Open launch console</.link>
          </div>

          <div class="al-launch-tags" aria-label="Launch via agent facts">
            <span class="al-launch-tag">CLI-first path</span>
            <span class="al-launch-tag">3-day auction</span>
            <span class="al-launch-tag">10% sold, 5% LP, 85% vesting</span>
          </div>

          <div class="al-stat-grid al-launch-stats">
            <.stat_card title="First step" value="Prelaunch wizard" hint="Save the plan before anything else" />
            <.stat_card title="Main path" value="Run -> monitor -> finalize" hint="Use the CLI for the operator flow" />
            <.stat_card title="Advanced work" value="Browser optional" hint="Web pages stay useful for review and live state" />
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
        id="launch-via-agent-path"
        class="al-launch-onboard al-panel"
        phx-hook="MissionMotion"
        aria-label="Launch via agent path"
      >
        <div class="al-onboard-summary">
          <p class="al-kicker">How to use agents</p>
          <h3>Keep the launch boring in the best way.</h3>
          <p class="al-subcopy">
            The ideal operator flow is one saved plan, one clear launch run, one monitoring pass,
            and one finalize step. The browser stays as a readable support surface, not the only
            place where the plan exists.
          </p>
        </div>

        <div class="al-onboard-grid">
          <article :for={item <- @golden_path} class="al-onboard-card">
            <p class="al-onboard-mark">{item.step}</p>
            <strong>{item.title}</strong>
            <p>{item.body}</p>
          </article>
        </div>
      </section>
    </.shell>
    """
  end
end
