// The Android side of Joshu (OrbitNativePlugin.java): the encrypted secret store, the Google sign-in
// loopback, bank texts and speech. In a plain browser (the ?demo preview) every call falls
// back to something harmless.
import { Capacitor, registerPlugin, PluginListenerHandle } from '@capacitor/core'

export interface Sms { id: string; address: string; body: string; date: number }

interface OrbitNative {
  loadSecrets(): Promise<{ json: string }>
  saveSecrets(o: { json: string }): Promise<void>
  startLoopback(): Promise<{ port: number }>
  waitLoopback(): Promise<{ query: string }>
  bringToFront(): Promise<void>
  smsPermission(o: { request: boolean }): Promise<{ granted: boolean }>
  readSms(o: { since: number; limit: number }): Promise<{ messages: Sms[] }>
  listen(o: { lang?: string }): Promise<{ text: string }>
  stopListening(): Promise<void>
  speak(o: { text: string; lang?: string }): Promise<void>
  stopSpeaking(): Promise<void>
  addListener(event: 'partial', fn: (d: { text: string }) => void): Promise<PluginListenerHandle>
  addListener(event: 'level', fn: (d: { level: number }) => void): Promise<PluginListenerHandle>
}

export const isNative = Capacitor.isNativePlatform()
export const native = registerPlugin<OrbitNative>('OrbitNative')
