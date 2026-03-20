export function animate(
  targets: unknown,
  options: Record<string, unknown>
): {
  cancel?: () => void
}

export function stagger(value: number, options?: Record<string, unknown>): unknown
