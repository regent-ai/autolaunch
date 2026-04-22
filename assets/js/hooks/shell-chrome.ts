import type { Hook } from "phoenix_live_view"

import { animate } from "../../vendor/anime.esm.js"

import {
  prefersReducedMotion,
  pulseElement,
} from "../regent_motion.ts"

interface ShellRoot extends HTMLElement {
  _shellChromeClick?: (event: Event) => void
  _shellChromeKeydown?: (event: KeyboardEvent) => void
}

interface CopyButton extends HTMLElement {
  _shellChromeResetTimer?: number
}

function reducedMotion(): boolean {
  return prefersReducedMotion()
}

function animateButton(button: HTMLElement): void {
  if (reducedMotion()) {
    pulseElement(button, 220)
    return
  }

  animate(button, {
    scale: [{ to: 0.985, duration: 80 }, { to: 1, duration: 220 }],
    translateY: [{ to: 1.5, duration: 80 }, { to: 0, duration: 220 }],
    duration: 300,
    ease: "outExpo",
  })
}

function copyValue(button: CopyButton): void {
  const value = button.dataset.copyValue || ""
  if (!value) return

  void navigator.clipboard.writeText(value)

  const originalLabel = button.dataset.copyLabel || button.textContent?.trim() || "Copy"
  button.dataset.copyLabel = originalLabel
  button.dataset.copyState = "copied"
  button.textContent = "Copied"

  animateButton(button)

  if (button._shellChromeResetTimer) {
    window.clearTimeout(button._shellChromeResetTimer)
  }

  button._shellChromeResetTimer = window.setTimeout(() => {
    button.dataset.copyState = "idle"
    button.textContent = originalLabel
  }, 1400)
}

function toggleTheme(button: HTMLElement): void {
  const current = document.documentElement.getAttribute("data-theme") || "light"
  const next = current === "light" ? "dark" : "light"

  animateButton(button)
  window.dispatchEvent(new CustomEvent("autolaunch:set-theme", { detail: { theme: next } }))
}

function focusGlobalSearch(event: KeyboardEvent): void {
  const key = event.key.toLowerCase()
  if (key !== "k" || !(event.metaKey || event.ctrlKey) || event.altKey || event.shiftKey) {
    return
  }

  const target = event.target as HTMLElement | null
  if (target && (target.matches("input, textarea, select") || target.isContentEditable)) {
    return
  }

  const search = document.getElementById("autolaunch-global-search") as HTMLInputElement | null
  if (!search) return

  event.preventDefault()
  search.focus()
  search.select()
}

export const ShellChrome: Hook = {
  mounted() {
    const root = this.el as ShellRoot
    root.dataset.shellChromeRoot = "true"

    root._shellChromeClick = (event: Event) => {
      const target = event.target as HTMLElement | null
      if (!target) return

      const owner = target.closest<HTMLElement>("[data-shell-chrome-root='true']")
      if (owner && owner !== root) return

      const copyButton = target.closest<CopyButton>("[data-copy-value]")
      if (copyButton && root.contains(copyButton)) {
        copyValue(copyButton)
        return
      }

      const themeButton = target.closest<HTMLElement>("[data-theme-action='toggle']")
      if (themeButton && root.contains(themeButton)) {
        toggleTheme(themeButton)
      }
    }

    root.addEventListener("click", root._shellChromeClick)

    root._shellChromeKeydown = (event: KeyboardEvent) => focusGlobalSearch(event)

    if (typeof window.addEventListener === "function") {
      window.addEventListener("keydown", root._shellChromeKeydown)
    }
  },

  destroyed() {
    const root = this.el as ShellRoot

    if (root._shellChromeClick) {
      root.removeEventListener("click", root._shellChromeClick)
    }

    if (root._shellChromeKeydown && typeof window.removeEventListener === "function") {
      window.removeEventListener("keydown", root._shellChromeKeydown)
    }

    delete root.dataset.shellChromeRoot
  },
}
