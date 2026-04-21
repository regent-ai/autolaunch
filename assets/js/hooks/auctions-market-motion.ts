import type { Hook } from "phoenix_live_view"

import { animate } from "../../vendor/anime.esm.js"

import {
  prefersReducedMotion,
  revealSequence,
} from "../../../../packages/regent_ui/assets/js/regent_motion"

interface MarketRoot extends HTMLElement {}
interface AnimatedCounterState {
  innerValue?: number
}

interface AnimatedProgressState {
  value?: number
}

type PulseAnimation = {
  pause?: () => void
  cancel?: () => void
}

type MarketRootState = MarketRoot & {
  __marketPulseAnimation?: PulseAnimation
}

function reducedMotion(): boolean {
  return prefersReducedMotion()
}

function animateCounters(root: HTMLElement): void {
  const counters = root.querySelectorAll<HTMLElement>("[data-market-counter]")

  for (const counter of counters) {
    const nextValue = Number(counter.dataset.marketCounter ?? "0")

    if (!Number.isFinite(nextValue)) continue

    const previousValue = Number(counter.dataset.marketCurrentValue ?? "0")
    const decimals = Number(counter.dataset.marketDecimals ?? "0")
    const prefix = counter.dataset.marketPrefix ?? ""
    const suffix = counter.dataset.marketSuffix ?? ""

    const render = (value: number) => {
      const formatted = value.toLocaleString(undefined, {
        minimumFractionDigits: decimals,
        maximumFractionDigits: decimals,
      })

      counter.textContent = `${prefix}${formatted}${suffix}`
    }

    if (reducedMotion()) {
      render(nextValue)
      counter.dataset.marketCurrentValue = String(nextValue)
      continue
    }

    animate(counter, {
      innerValue: [previousValue, nextValue],
      duration: 720,
      ease: "outExpo",
      round: decimals === 0 ? 1 : 100,
      onUpdate(animation: { animatables: Array<{ target: AnimatedCounterState }> }) {
        const value = Number(animation.animatables[0]?.target.innerValue ?? nextValue)
        render(value)
      },
      onComplete() {
        render(nextValue)
        counter.dataset.marketCurrentValue = String(nextValue)
      },
    })
  }
}

function animateProgress(root: HTMLElement): void {
  const progressBars = root.querySelectorAll<HTMLElement>("[data-market-progress]")

  for (const bar of progressBars) {
    const nextValue = Number(bar.dataset.marketProgress ?? "0")
    const boundedValue = Math.max(0, Math.min(100, nextValue))
    const currentValue = Number(bar.dataset.marketCurrentProgress ?? "0")

    if (reducedMotion()) {
      bar.style.transform = `scaleX(${boundedValue / 100})`
      bar.dataset.marketCurrentProgress = String(boundedValue)
      continue
    }

    animate({ value: currentValue }, {
      value: boundedValue,
      duration: 900,
      ease: "outQuart",
      onUpdate(animation: { animatables: Array<{ target: AnimatedProgressState }> }) {
        const value = Number(animation.animatables[0]?.target.value ?? boundedValue)
        bar.style.transform = `scaleX(${value / 100})`
      },
      onComplete() {
        bar.style.transform = `scaleX(${boundedValue / 100})`
        bar.dataset.marketCurrentProgress = String(boundedValue)
      },
    })
  }
}

function stopPulse(root: MarketRootState): void {
  root.__marketPulseAnimation?.pause?.()
  root.__marketPulseAnimation?.cancel?.()
  delete root.__marketPulseAnimation
}

function animatePulse(root: MarketRootState): void {
  const pulse = root.querySelector<HTMLElement>("[data-market-pulse]")
  if (!pulse || reducedMotion()) {
    stopPulse(root)
    return
  }

  stopPulse(root)

  root.__marketPulseAnimation = animate(pulse, {
    scale: [0.9, 1.08],
    opacity: [0.55, 1],
    duration: 1800,
    ease: "inOutSine",
    alternate: true,
    loop: true,
  })
}

function animateRoot(root: MarketRootState): void {
  if (!reducedMotion()) {
    revealSequence(root, "[data-market-reveal]", {
      translateY: 18,
      delay: 70,
      duration: 560,
    })
  }

  animateCounters(root)
  animateProgress(root)
  animatePulse(root)
}

export const AuctionsMarketMotion: Hook = {
  mounted() {
    animateRoot(this.el as MarketRootState)
  },

  updated() {
    animateRoot(this.el as MarketRootState)
  },

  destroyed() {
    stopPulse(this.el as MarketRootState)
  },
}
