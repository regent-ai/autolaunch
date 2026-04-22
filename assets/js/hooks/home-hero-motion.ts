import type { Hook } from "phoenix_live_view"

import { animate } from "../../vendor/anime.esm.js"

import {
  prefersReducedMotion,
  revealSequence,
} from "../regent_motion"

interface HomeHeroRoot extends HTMLElement {}

function reducedMotion(): boolean {
  return prefersReducedMotion()
}

function animateOrbit(root: HTMLElement, selector: string, duration: number, direction: 1 | -1): void {
  const target = root.querySelector<HTMLElement>(selector)
  if (!target) return

  animate(target, {
    rotate: direction > 0 ? [0, 360] : [360, 0],
    duration,
    ease: "linear",
    loop: true,
  })
}

function animateSigil(root: HTMLElement): void {
  const sigil = root.querySelector<HTMLElement>(".al-homepage-sigil")
  const halo = root.querySelector<HTMLElement>(".al-homepage-sigil-halo")

  if (sigil) {
    animate(sigil, {
      translateY: [-6, 6],
      scale: [0.985, 1.015],
      duration: 4600,
      ease: "inOutSine",
      alternate: true,
      loop: true,
    })
  }

  if (halo) {
    animate(halo, {
      scale: [0.96, 1.04],
      opacity: [0.78, 1],
      duration: 3800,
      ease: "inOutSine",
      alternate: true,
      loop: true,
    })
  }
}

export const HomeHeroMotion: Hook = {
  mounted() {
    const root = this.el as HomeHeroRoot

    if (reducedMotion()) return

    revealSequence(root, "[data-home-hero-reveal]", {
      translateY: 16,
      delay: 50,
      duration: 440,
    })

    animateOrbit(root, ".al-homepage-orbit", 42000, 1)
    animateOrbit(root, ".al-homepage-orbit--inner", 32000, -1)
    animateSigil(root)
  },
}
