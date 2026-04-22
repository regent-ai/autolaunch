import type { Hook } from "phoenix_live_view"

import {
  prefersReducedMotion,
  revealSequence,
} from "../regent_motion"

interface MotionRoot extends HTMLElement {}

function reducedMotion(): boolean {
  return prefersReducedMotion()
}

function animateIntro(root: MotionRoot): void {
  const items = Array.from(root.children).filter(
    (child): child is HTMLElement => child instanceof HTMLElement && !child.hidden,
  )

  if (items.length < 2) {
    return
  }

  revealSequence(root, ":scope > *", {
    translateY: 14,
    delay: 40,
    duration: 380,
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
