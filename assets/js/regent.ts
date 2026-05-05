import type { HooksOptions } from "phoenix_live_view"

import type { HeerichConstructor } from "../../../design-system/regent_ui/assets/js/heerich_types"
import { hooks as regentUiHooks } from "../../../design-system/regent_ui/assets/js/hooks"

export const hooks: HooksOptions = {
  ...regentUiHooks,
}

export function installHeerich(HeerichCtor: unknown): void {
  window.Heerich = HeerichCtor as HeerichConstructor
}
