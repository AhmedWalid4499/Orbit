/// <reference types="vite/client" />
import type { OrbitBridge } from '../../preload/index'

declare global {
  interface Window { orbit: OrbitBridge }
}
export {}
