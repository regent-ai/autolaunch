import assert from "node:assert/strict"
import { afterEach, beforeEach, describe, it } from "node:test"

import { WelcomeModal } from "./welcome-modal.ts"

class FakeClassList {
  private values = new Set<string>()

  add(...tokens: string[]) {
    tokens.forEach((token) => this.values.add(token))
  }

  remove(...tokens: string[]) {
    tokens.forEach((token) => this.values.delete(token))
  }

  contains(token: string) {
    return this.values.has(token)
  }
}

class FakeButton {
  private clickHandlers = new Set<(event: Event) => void>()
  dataset: Record<string, string> = {}
  textContent = ""

  constructor(dataset: Record<string, string> = {}) {
    this.dataset = dataset
  }

  addEventListener(eventName: string, handler: (event: Event) => void) {
    if (eventName === "click") this.clickHandlers.add(handler)
  }

  removeEventListener(eventName: string, handler: (event: Event) => void) {
    if (eventName === "click") this.clickHandlers.delete(handler)
  }

  click() {
    const event = { target: this } as unknown as Event
    this.clickHandlers.forEach((handler) => handler(event))
  }
}

class FakeWelcomeRoot {
  dataset: Record<string, string> = {}
  classList = new FakeClassList()
  hidden = true
  attributes = new Map<string, string>()
  continueButton = new FakeButton()
  closeButton = new FakeButton()

  querySelector<T extends FakeButton>(selector: string): T | null {
    if (selector === "[data-welcome-continue]") return this.continueButton as T
    if (selector === "[data-welcome-close]") return this.closeButton as T
    return null
  }

  setAttribute(name: string, value: string) {
    this.attributes.set(name, value)
  }
}

const originalWindow = globalThis.window
const originalDocument = globalThis.document
const originalHTMLElement = globalThis.HTMLElement
const originalCustomEvent = globalThis.CustomEvent

function mountWelcomeModal(root: FakeWelcomeRoot) {
  const mounted = WelcomeModal.mounted
  assert.ok(mounted, "WelcomeModal.mounted must exist")
  mounted.call({ el: root } as never)
}

describe("welcome-modal hook", () => {
  let cookieValue = ""

  beforeEach(() => {
    cookieValue = ""

    globalThis.HTMLElement = FakeWelcomeRoot as unknown as typeof HTMLElement
    globalThis.CustomEvent = class {} as unknown as typeof CustomEvent
    globalThis.document = {
      get cookie() {
        return cookieValue
      },
      set cookie(value: string) {
        cookieValue = value
      },
    } as unknown as Document
    globalThis.window = {
      location: { protocol: "https:" },
      addEventListener() {},
      removeEventListener() {},
      matchMedia: () =>
        ({
          matches: true,
          media: "(prefers-reduced-motion: reduce)",
          onchange: null,
          addListener() {},
          removeListener() {},
          addEventListener() {},
          removeEventListener() {},
          dispatchEvent() {
            return true
          },
        }) as MediaQueryList,
    } as unknown as Window & typeof globalThis
  })

  afterEach(() => {
    globalThis.window = originalWindow
    globalThis.document = originalDocument
    globalThis.HTMLElement = originalHTMLElement
    globalThis.CustomEvent = originalCustomEvent
  })

  it("opens once and stores a cookie when continued", () => {
    const root = new FakeWelcomeRoot()
    root.dataset.cookieName = "autolaunch_welcome_seen"

    mountWelcomeModal(root)

    assert.equal(root.hidden, false)
    assert.ok(root.classList.contains("modal-open"))

    root.continueButton.click()

    assert.equal(root.hidden, true)
    assert.match(cookieValue, /autolaunch_welcome_seen=1/)
    assert.match(cookieValue, /Max-Age=31536000/)
  })

  it("stays hidden once the cookie exists", () => {
    cookieValue = "autolaunch_welcome_seen=1"

    const root = new FakeWelcomeRoot()
    root.dataset.cookieName = "autolaunch_welcome_seen"

    mountWelcomeModal(root)

    assert.equal(root.hidden, true)
    refute(root.classList.contains("modal-open"))
  })
})

function refute(value: boolean) {
  assert.equal(value, false)
}
