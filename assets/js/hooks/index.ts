import type { HooksOptions } from "phoenix_live_view"

import { hooks as regentHooks } from "../../../../packages/regent_ui/assets/js/regent"
import { AgentBookFlow } from "./agentbook-flow"
import { MissionMotion } from "./mission-motion"
import { PrivyAuth } from "./privy-auth"
import { ShellChrome } from "./shell-chrome"
import { WelcomeModal } from "./welcome-modal"
import { WalletTxButton } from "./wallet-tx-button"
import { XLinkFlow } from "./x-link-flow"

export const hooks: HooksOptions = {
  ...regentHooks,
  AgentBookFlow,
  MissionMotion,
  PrivyAuth,
  ShellChrome,
  WelcomeModal,
  WalletTxButton,
  XLinkFlow,
}
