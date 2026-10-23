import Foundation
import SwiftData
import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Global hot key (⌥Space)

/// System-wide shortcut with separate press and release callbacks.
/// ⌥Space: tap to open quick capture, hold to talk (voice capture).
final class HotKey {
    private static var handlers: [UInt32: (press: () -> Void, release: (() -> Void)?)] = [:]
    private static var installed = false
    private var ref: EventHotKeyRef?

    init(id: UInt32 = 1, keyCode: Int = kVK_Space, modifiers: Int = optionKey,
         onPress: @escaping () -> Void, onRelease: (() -> Void)? = nil) {
        HotKey.installIfNeeded()
        HotKey.handlers[id] = (onPress, onRelease)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F524254), id: id) // 'ORBT'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let id = hk.id
            DispatchQueue.main.async {
                guard let h = HotKey.handlers[id] else { return }
                if pressed { h.press() } else { h.release?() }
            }
            return noErr
        }, specs.count, &specs, nil, nil)
    }
}

// MARK: - Floating capture panel

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor
final class CapturePanel {
    static let shared = CapturePanel()
    private var panel: NSPanel?
    var container: ModelContainer?

    func toggle() {
        if let panel, panel.isVisible { panel.orderOut(nil); return }
        show()
    }

    func show() {
        guard let container else { return }
        let panel = self.panel ?? makePanel(container: container)
        self.panel = panel
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - f.height * 0.28))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .captureOpened, object: nil)
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel(container: ModelContainer) -> NSPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 150),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: QuickCaptureView().modelContainer(container))
        host.sizingOptions = [.preferredContentSize]
        panel.contentView = host
        return panel
    }
}

extension Notification.Name {
    static let captureOpened = Notification.Name("orbit.captureOpened")
}
