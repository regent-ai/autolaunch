export {}

import type { HeerichConstructor } from "../../../../design-system/regent_ui/assets/js/heerich_types"

declare global {
  interface Window {
    Heerich?: HeerichConstructor
  }
}
