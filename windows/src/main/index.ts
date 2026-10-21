import { app, BrowserWindow, ipcMain, shell, nativeTheme } from 'electron'
import { autoUpdater } from 'electron-updater'
import { join } from 'path'
import { readFileSync } from 'fs'

// Google sign-in (through Supabase) comes back to Orbit on this link, same as the Mac app.
const PROTOCOL = 'com.personal.orbit'
let win: BrowserWindow | null = null
let pendingCallback: string | null = null

if (!app.requestSingleInstanceLock()) app.quit()

if (process.defaultApp && process.argv.length >= 2) {
  app.setAsDefaultProtocolClient(PROTOCOL, process.execPath, [join(process.argv[1])])
} else {
  app.setAsDefaultProtocolClient(PROTOCOL)
}

function deliverCallback(url: string | undefined): void {
  if (!url || !url.startsWith(`${PROTOCOL}://`)) return
  if (win) {
    win.webContents.send('auth-callback', url)
    if (win.isMinimized()) win.restore()
    win.focus()
  } else {
    pendingCallback = url
  }
}

// Windows: the link arrives as an argument to a second launch of Orbit.
app.on('second-instance', (_e, argv) => deliverCallback(argv.find((a) => a.startsWith(`${PROTOCOL}://`))))
// macOS (development): the link arrives as an event.
app.on('open-url', (e, url) => { e.preventDefault(); deliverCallback(url) })

function supabaseConfig(): { url: string; key: string } {
  const file = app.isPackaged ? join(process.resourcesPath, 'Supabase.json') : join(__dirname, '../../../Support/Supabase.json')
  try { return JSON.parse(readFileSync(file, 'utf8')) } catch { return { url: '', key: '' } }
}

function createWindow(): void {
  const dark = nativeTheme.shouldUseDarkColors
  win = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1180,
    minHeight: 760,
    show: false,
    backgroundColor: dark ? '#111113' : '#ffffff',
    title: 'Orbit',
    icon: join(__dirname, '../../build/icon.png'),
    ...(process.platform === 'darwin'
      ? { titleBarStyle: 'hiddenInset' as const }
      : { titleBarStyle: 'hidden' as const, titleBarOverlay: { color: '#00000000', symbolColor: dark ? '#f4f4f5' : '#111111', height: 44 } }),
    webPreferences: { preload: join(__dirname, '../preload/index.js'), sandbox: false, contextIsolation: true },
  })
  win.on('ready-to-show', () => win?.show())
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:\/\//.test(url)) shell.openExternal(url)
    return { action: 'deny' }
  })
  nativeTheme.on('updated', () => {
    if (process.platform === 'win32') {
      win?.setTitleBarOverlay({ color: '#00000000', symbolColor: nativeTheme.shouldUseDarkColors ? '#f4f4f5' : '#111111', height: 44 })
    }
  })
  if (process.env['ELECTRON_RENDERER_URL']) win.loadURL(process.env['ELECTRON_RENDERER_URL'])
  else win.loadFile(join(__dirname, '../renderer/index.html'))
  win.webContents.once('did-finish-load', () => {
    const fromArgs = process.argv.find((a) => a.startsWith(`${PROTOCOL}://`))
    deliverCallback(pendingCallback ?? fromArgs)
    pendingCallback = null
  })
}

// MARK: Updates (Windows installs only)

type UpdateState = { state: 'idle' | 'checking' | 'available' | 'downloading' | 'ready' | 'none' | 'error'; version?: string; progress?: number; message?: string }
function sendUpdate(s: UpdateState): void { win?.webContents.send('update-status', s) }

autoUpdater.autoDownload = true
autoUpdater.on('checking-for-update', () => sendUpdate({ state: 'checking' }))
autoUpdater.on('update-available', (i) => sendUpdate({ state: 'available', version: i.version }))
autoUpdater.on('update-not-available', () => sendUpdate({ state: 'none' }))
autoUpdater.on('download-progress', (p) => sendUpdate({ state: 'downloading', progress: p.percent / 100 }))
autoUpdater.on('update-downloaded', (i) => sendUpdate({ state: 'ready', version: i.version }))
autoUpdater.on('error', (e) => sendUpdate({ state: 'error', message: String(e?.message ?? e) }))

function canUpdate(): boolean { return app.isPackaged && process.platform === 'win32' }

// MARK: Bridge to the window

ipcMain.handle('config', () => ({ supabase: supabaseConfig(), version: app.getVersion(), platform: process.platform, canUpdate: canUpdate() }))
ipcMain.handle('open-external', (_e, url: string) => { if (/^https?:\/\//.test(url)) shell.openExternal(url) })
ipcMain.handle('check-updates', async () => {
  if (!canUpdate()) { sendUpdate({ state: 'none', message: 'Updates are installed by the Windows version.' }); return }
  try { await autoUpdater.checkForUpdates() } catch (e) { sendUpdate({ state: 'error', message: String(e) }) }
})
ipcMain.handle('install-update', () => autoUpdater.quitAndInstall())

app.whenReady().then(() => {
  createWindow()
  if (canUpdate()) {
    autoUpdater.checkForUpdates().catch(() => {})
    setInterval(() => autoUpdater.checkForUpdates().catch(() => {}), 6 * 3600 * 1000)
  }
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow() })
})

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })
