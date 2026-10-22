// Lets any screen open the Ask panel, optionally with a first message (e.g. "Discuss with Ask" on Money).
type Listener = (seed?: string) => void
const listeners = new Set<Listener>()
export function openAsk(seed?: string): void { listeners.forEach((l) => l(seed)) }
export function onOpenAsk(l: Listener): () => void { listeners.add(l); return () => { listeners.delete(l) } }
