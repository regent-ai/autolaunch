import type { HooksOptions } from "phoenix_live_view"

export const hooks: HooksOptions = {}

export function installHeerich(HeerichCtor: unknown): void {
  window.Heerich = HeerichCtor
}
