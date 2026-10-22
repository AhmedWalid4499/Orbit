import Foundation
import SwiftData
import AppKit
import Carbon.HIToolbox
import SwiftUI

extension QuickParser.Result {
    /// Saves the parsed item into the store.
    func save(in context: ModelContext) {
        switch kind {
        case .task:
            context.insert(TaskItem(title: title, area: area ?? .personal, due: date, priority: priority))
        case .event:
            let start = date ?? .now
            context.insert(EventItem(title: title, start: start, end: start.adding(minutes: durationMinutes ?? 60), area: area ?? .personal))
        case .expense, .income:
            context.insert(Transaction(title: title.isEmpty ? (category ?? "Expense") : title,
                                       amount: amount ?? 0, category: category ?? "General"))
        case .note:
            context.insert(Note(title: title.isEmpty ? "Untitled" : title))
        case .journal:
            let today = Date.now.startOfDay
            let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.isJournal && $0.createdAt >= today })
            if let entry = try? context.fetch(descriptor).first {
                entry.body += (entry.body.isEmpty ? "" : "\n") + title
                entry.updatedAt = .now
            } else {
                context.insert(Note(title: Date.now.formatted(date: .complete, time: .omitted), body: title, isJournal: true))
            }
        }
        try? context.save()
    }
}

// MARK: - Capture engine (shared by ⌥Space and the Today bar)

@MainActor
enum CaptureEngine {
    /// Saves free text as one or more items, using Claude when smart capture is on and the offline parser otherwise.
    /// Returns a short summary of what was saved.
    static func capture(_ raw: String, context: ModelContext) async -> String {
        var items = [QuickParser.parse(raw)]
        var note = ""
        if AIAssistant.shared.smartCaptureActive {
            do {
                let smart = try await AIAssistant.shared.smartParse(raw)
                if !smart.isEmpty { items = smart }
            } catch {
                note = " (offline parser)"
            }
        }
        let valid = items.filter { !$0.title.isEmpty || $0.amount != nil }
        valid.forEach { $0.save(in: context) }
        return valid.map(\.summary).joined(separator: "  |  ") + note
    }
}

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
