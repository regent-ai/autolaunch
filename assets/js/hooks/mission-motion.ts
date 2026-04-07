import type { Hook } from "phoenix_live_view"

import {
  prefersReducedMotion,
  revealSequence,
} from "../../../../packages/regent_ui/assets/js/regent_motion"

interface MotionRoot extends HTMLElement {}

function reducedMotion(): boolean {
  return prefersReducedMotion()
}

function animateIntro(root: MotionRoot): void {
  const selectors =
    root.id === "launch-cli-hero" || root.id === "auction-detail-hero" || root.id === "positions-hero" ||
        root.id === "subject-hero" || root.id === "contracts-hero" || root.id === "profile-hero" ||
        root.id === "agentbook-hero" || root.id === "auctions-intro" || root.id === "launch-via-agent-hero"
      ? ":scope > *"
      : root.id === "launch-cli-steps" || root.id === "auctions-grid" || root.id === "profile-sections" ||
          root.id === "subject-primary-actions" || root.id === "subject-secondary-actions"
        ? ":scope > *"
        : ""

  if (selectors === "") {
    return
  }

  revealSequence(root, selectors, {
    translateY: 18,
    delay: 70,
    duration: 560,
  })
}

export const MissionMotion: Hook = {
  mounted() {
    const root = this.el as MotionRoot
    if (reducedMotion()) return
    animateIntro(root)
  },

  updated() {},
  destroyed() {},
}
