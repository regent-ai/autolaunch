export class LocalStorage {}

export class Privy {
  constructor(options: Record<string, unknown>)
  initialize(): Promise<void>
  getAccessToken(): Promise<string | null>
  user: {
    get(): Promise<{ user?: unknown }>
  }
  auth: {
    oauth: {
      generateURL(provider: string, redirectURI: string): Promise<{ url: string }>
      loginWithCode(code: string, state: string, provider: string): Promise<unknown>
    }
    logout(args: { userId: string }): Promise<void>
  }
}
