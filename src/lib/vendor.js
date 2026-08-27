// Tiny local equivalent of the class combiner used by shadcn/ui.
export function clsx(...inputs) {
  return inputs
    .flatMap((input) => {
      if (!input) return []
      if (typeof input === 'string' || typeof input === 'number') return [input]
      if (Array.isArray(input)) return input
      if (typeof input === 'object') return Object.entries(input).filter(([, value]) => Boolean(value)).map(([key]) => key)
      return []
    })
    .join(' ')
}
