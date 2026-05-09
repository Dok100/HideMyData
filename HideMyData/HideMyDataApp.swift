import SwiftUI
import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let showClipboardAnonymizer = Notification.Name("HMD.showClipboardAnonymizer")
}

@main
struct HideMyDataApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var updater = UpdaterModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(updater)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen…") {
                    updater.checkForUpdates()
                }
            }

            CommandMenu("Anonymisieren") {
                Button("Zwischenablage anonymisieren…") {
                    NotificationCenter.default.post(name: .showClipboardAnonymizer, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let globalHotKeyController = GlobalHotKeyController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        globalHotKeyController.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKeyController.unregister()
    }
}

@MainActor
private final class GlobalHotKeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func register() {
        guard hotKeyRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
                controller.handleHotKeyEvent(event)
                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        guard status == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: OSType(0x484D4441), id: UInt32(1)) // HMDA
        let modifiers = UInt32(cmdKey | shiftKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_A),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
        }
    }

    private func handleHotKeyEvent(_ event: EventRef?) {
        guard let event else { return }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.id == 1 else { return }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .showClipboardAnonymizer, object: nil)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
