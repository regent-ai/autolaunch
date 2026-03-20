import "phoenix_html"

import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

import { hooks } from "./hooks/index"

const csrfToken =
  (document.querySelector("meta[name='csrf-token']") as HTMLMetaElement | null)?.content || ""

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks,
})

topbar.config({ barColors: { 0: "#0ea5e9" }, shadowColor: "rgba(1, 9, 20, 0.35)" })
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

liveSocket.connect()

;(window as Window & { liveSocket?: unknown }).liveSocket = liveSocket
