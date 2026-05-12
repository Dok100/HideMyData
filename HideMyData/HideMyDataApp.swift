import SwiftUI
import AppKit
import Carbon.HIToolbox

enum AppPreferencesKeys {
    static let appearanceMode = "Inkognito.appearanceMode"
    static let recentsEnabled = "Inkognito.recents.enabled"
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var description: String {
        switch self {
        case .system: "Folgt automatisch dem macOS-Erscheinungsbild."
        case .light: "Verwendet dauerhaft das helle Erscheinungsbild."
        case .dark: "Verwendet dauerhaft das dunkle Erscheinungsbild."
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static func from(rawValue: String) -> AppAppearanceMode {
        AppAppearanceMode(rawValue: rawValue) ?? .system
    }

    static func apply(rawValue: String) {
        let mode = AppAppearanceMode.from(rawValue: rawValue)
        NSApp.appearance = mode.nsAppearance
    }
}

extension Notification.Name {
    static let showClipboardAnonymizer = Notification.Name("HMD.showClipboardAnonymizer")
}

@main
struct HideMyDataApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Anonymisieren") {
                Button("Zwischenablage anonymisieren…") {
                    NotificationCenter.default.post(name: .showClipboardAnonymizer, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }

        Settings {
            AppSettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let globalHotKeyController = GlobalHotKeyController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let storedAppearance = UserDefaults.standard.string(forKey: AppPreferencesKeys.appearanceMode) ?? AppAppearanceMode.system.rawValue
        AppAppearanceMode.apply(rawValue: storedAppearance)
        globalHotKeyController.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKeyController.unregister()
    }
}

struct AppSettingsView: View {
    @AppStorage(AppPreferencesKeys.appearanceMode) private var appearanceModeRawValue = AppAppearanceMode.system.rawValue
    @AppStorage(AppPreferencesKeys.recentsEnabled) private var recentsEnabled = true

    private var selectedAppearance: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode.from(rawValue: appearanceModeRawValue) },
            set: { newValue in
                appearanceModeRawValue = newValue.rawValue
                AppAppearanceMode.apply(rawValue: newValue.rawValue)
            }
        )
    }

    var body: some View {
        Form {
            Section("Erscheinungsbild") {
                Picker("Darstellung", selection: selectedAppearance) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedAppearance.wrappedValue.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Datenschutz") {
                Toggle("Zuletzt verwendete Dateien merken", isOn: $recentsEnabled)

                Text("Speichert Dateiverweise und Vorschaubilder lokal auf diesem Mac, damit zuletzt geoeffnete Dokumente schneller wieder verfuegbar sind.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
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
