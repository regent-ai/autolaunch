import type { Hook } from "phoenix_live_view"

import { animate } from "../../vendor/anime.esm.js"

import { prefersReducedMotion } from "../../../../packages/regent_ui/assets/js/regent_motion.ts"

interface WelcomeModalRoot extends HTMLElement {
  _welcomeModalDismiss?: (event: Event) => void
  _welcomeModalKeydown?: (event: KeyboardEvent) => void
}

const DEFAULT_COOKIE_NAME = "autolaunch_welcome_seen"
const COOKIE_TTL_SECONDS = 60 * 60 * 24 * 365

function readCookie(name: string): string | null {
  const prefix = `${name}=`
  const entry = document.cookie
    .split(";")
    .map((value) => value.trim())
    .find((value) => value.startsWith(prefix))

  return entry ? decodeURIComponent(entry.slice(prefix.length)) : null
}

function writeCookie(name: string, value: string): void {
  const secure = window.location.protocol === "https:" ? "; Secure" : ""
  document.cookie = `${name}=${encodeURIComponent(value)}; Path=/; Max-Age=${COOKIE_TTL_SECONDS}; SameSite=Lax${secure}`
}

function closeModal(root: WelcomeModalRoot): void {
  root.classList.remove("modal-open")
  root.setAttribute("aria-hidden", "true")
  root.hidden = true
}

function openModal(root: WelcomeModalRoot): void {
  root.hidden = false
  root.classList.add("modal-open")
  root.setAttribute("aria-hidden", "false")

  const box = root.querySelector<HTMLElement>(".modal-box")
  if (!box) return

  if (prefersReducedMotion()) {
    box.style.opacity = "1"
    box.style.transform = "none"
    return
  }

  animate(box, {
    opacity: [0, 1],
    translateY: [22, 0],
    scale: [0.98, 1],
    duration: 540,
    ease: "outExpo",
  })
}

export const WelcomeModal: Hook = {
  mounted() {
    const root = this.el as WelcomeModalRoot
    const cookieName = root.dataset.cookieName?.trim() || DEFAULT_COOKIE_NAME

    if (readCookie(cookieName) === "1") {
      closeModal(root)
      return
    }

    const dismiss = () => {
      writeCookie(cookieName, "1")
      closeModal(root)
    }

    const onKeydown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !root.hidden) {
        dismiss()
      }
    }

    root._welcomeModalDismiss = dismiss
    root._welcomeModalKeydown = onKeydown

    root.querySelector<HTMLButtonElement>("[data-welcome-continue]")?.addEventListener(
      "click",
      dismiss,
    )
    root.querySelector<HTMLButtonElement>("[data-welcome-close]")?.addEventListener("click", dismiss)
    window.addEventListener("keydown", onKeydown)

    openModal(root)
  },

  destroyed() {
    const root = this.el as WelcomeModalRoot

    if (root._welcomeModalDismiss) {
      root
        .querySelector<HTMLButtonElement>("[data-welcome-continue]")
        ?.removeEventListener("click", root._welcomeModalDismiss)
      root
        .querySelector<HTMLButtonElement>("[data-welcome-close]")
        ?.removeEventListener("click", root._welcomeModalDismiss)
    }

    if (root._welcomeModalKeydown) {
      window.removeEventListener("keydown", root._welcomeModalKeydown)
    }
  },
}
