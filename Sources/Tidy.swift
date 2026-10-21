import AppKit
import Security
import ServiceManagement
import SwiftUI

struct Config: Codable, Equatable {
    var style = "natural"
    var model = "haiku"
    var extra = ""
    var copyToClipboard = true
    var fallbackLocal = true
    var hudSize = "medium"
    var hotkey = defaultHotkey
    var showInMenuBar = true
    var vocabulary = ""
    var orbState = "composing"
    var hudText = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        style = value(.style, style)
        model = value(.model, model)
        extra = value(.extra, extra)
        copyToClipboard = value(.copyToClipboard, copyToClipboard)
        fallbackLocal = value(.fallbackLocal, fallbackLocal)
        hudSize = value(.hudSize, hudSize)
        hotkey = normalizedHotkey(value(.hotkey, hotkey))
        showInMenuBar = value(.showInMenuBar, showInMenuBar)
        vocabulary = value(.vocabulary, vocabulary)
        if vocabulary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { vocabulary = "" }
        orbState = value(.orbState, orbState)
        hudText = value(.hudText, hudText)
        if !orbChoices.contains(where: { $0.rawValue == orbState }) { orbState = "composing" }
    }

    static func read() -> Config? {
        guard let data = try? Data(contentsOf: Paths.config) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    static func load() -> Config {
        read() ?? Config()
    }
}

enum FirstLaunch {
    nonisolated(unsafe) static var fresh = false

}

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let configDir = home.appendingPathComponent(".config/\(Identity.configDirName)")
    static let config = configDir.appendingPathComponent("config.json")
    static let script = Bundle.main.url(forResource: "fixer", withExtension: nil)
        ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/fixer")
    static let localHelper = Bundle.main.url(forAuxiliaryExecutable: "fixer-local")
        ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/fixer-local")

    static func securePermissions() {
        let fm = FileManager.default
        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: configDir.path)
        if fm.fileExists(atPath: config.path) {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        }
    }

    static var bundleIntact: Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
    }
}

struct Option: Identifiable {
    let id: String
    let name: String
    let blurb: String
}

let styles = [
    Option(id: "natural", name: "Natural", blurb: "Casual and short, like texting. For Slack and chat."),
    Option(id: "official", name: "Official", blurb: "Polite full sentences, no slang. For emails."),
    Option(id: "minimal", name: "Typos only", blurb: "Fixes spelling and grammar, changes nothing else."),
]

let models = [
    Option(id: "haiku", name: "Haiku 5.5", blurb: "Claude Haiku 5.5 (claude-haiku-5-5) · ~3 s · uses your Claude account."),
    Option(id: "local", name: "Local", blurb: "Apple Foundation Model · on-device · offline · free · <1 s."),
]

let hudSizes = [
    Option(id: "off", name: "Off", blurb: ""),
    Option(id: "small", name: "Small", blurb: ""),
    Option(id: "medium", name: "Medium", blurb: ""),
    Option(id: "large", name: "Large", blurb: ""),
]

final class Store: ObservableObject {
    static let shared = Store()

    @Published var config: Config {
        didSet {
            guard config != oldValue else { return }
            save()
            if config.hotkey != oldValue.hotkey { HotKey.shared.register(config.hotkey) }
            if config.showInMenuBar != oldValue.showInMenuBar { StatusBar.shared.setVisible(config.showInMenuBar) }
        }
    }

    private var unreadable = false

    var hotkeyBinding: Binding<RecordedShortcut?> {
        Binding(get: { hotkeyShortcut(self.config.hotkey) },
                set: { self.config.hotkey = $0?.storageID ?? "off" })
    }

    init() {
        Paths.securePermissions()
        let exists = FileManager.default.fileExists(atPath: Paths.config.path)
        if let c = Config.read() {
            config = c
        } else {
            config = Config()
            unreadable = exists
        }
        if !models.contains(where: { $0.id == config.model }) { config.model = "haiku" }
        if !unreadable { save() }
    }

    func save() {
        Paths.securePermissions()
        let fm = FileManager.default
        if unreadable {
            let backup = Paths.configDir.appendingPathComponent("config.unreadable.json")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: Paths.config, to: backup)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            unreadable = false
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(config) else { return }
        try? data.write(to: Paths.config, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.config.path)
    }
}

let fixTimeout: TimeInterval = 80

func runFix(_ text: String) async -> (ok: Bool, text: String, engine: String) {
    await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async {
            guard Paths.bundleIntact else {
                cont.resume(returning: (false, "\(Identity.appName)'s files were changed. Rebuild or reinstall \(Identity.appName).", ""))
                return
            }
            var env = ProcessInfo.processInfo.environment
            env["FIXER_STRICT"] = "1"
            env["FIXER_SHOW_ENGINE"] = "1"
            env["FIXER_NO_SIGNAL"] = "1"
            guard let r = Spawn.run(Paths.script.path, input: Data(text.utf8), env: env, timeout: fixTimeout) else {
                cont.resume(returning: (false, "Could not run \(Paths.script.path)", ""))
                return
            }
            if r.timedOut {
                cont.resume(returning: (false, "Timed out", ""))
                return
            }
            let errText = String(decoding: r.err, as: UTF8.self)
            if r.status == 0 {
                let engine = errText.split(separator: "\n")
                    .first { $0.hasPrefix("engine: ") }
                    .map { String($0.dropFirst(8)) } ?? ""
                cont.resume(returning: (true, String(decoding: r.out, as: UTF8.self), engine))
            } else {
                cont.resume(returning: (false, errText, ""))
            }
        }
    }
}

enum Spawn {
    struct Result {
        let status: Int32
        let out: Data
        let err: Data
        let timedOut: Bool
    }

    static func run(_ path: String, input: Data, env: [String: String], timeout: TimeInterval) -> Result? {
        var inP: [Int32] = [-1, -1], outP: [Int32] = [-1, -1], errP: [Int32] = [-1, -1]
        guard pipe(&inP) == 0, pipe(&outP) == 0, pipe(&errP) == 0 else { return nil }
        _ = fcntl(inP[1], F_SETNOSIGPIPE, 1)

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, inP[0], 0)
        posix_spawn_file_actions_adddup2(&actions, outP[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errP[1], 2)

        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attr, 0)

        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
        let envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, path, &actions, &attr, argv, envp)
        close(inP[0]); close(outP[1]); close(errP[1])
        guard rc == 0 else {
            close(inP[1]); close(outP[0]); close(errP[0])
            return nil
        }

        let group = DispatchGroup()
        var out = Data(), err = Data()
        let readOut = FileHandle(fileDescriptor: outP[0], closeOnDealloc: true)
        let readErr = FileHandle(fileDescriptor: errP[0], closeOnDealloc: true)
        group.enter()
        DispatchQueue.global().async { out = readOut.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { err = readErr.readDataToEndOfFile(); group.leave() }
        DispatchQueue.global().async {
            let writer = FileHandle(fileDescriptor: inP[1], closeOnDealloc: true)
            try? writer.write(contentsOf: input)
            try? writer.close()
        }

        let lock = NSLock()
        var timedOut = false
        let killer = DispatchWorkItem {
            lock.lock(); timedOut = true; lock.unlock()
            killpg(pid, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { killpg(pid, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        killer.cancel()
        lock.lock(); let didTimeOut = timedOut; lock.unlock()
        if didTimeOut { killpg(pid, SIGKILL) }
        guard group.wait(timeout: .now() + 3) == .success else {
            return Result(status: -1, out: Data(), err: Data(), timedOut: didTimeOut)
        }
        let code: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        return Result(status: code, out: out, err: err, timedOut: didTimeOut)
    }
}

final class SettingsTabs: NSTabViewController {
    static let lastKey = "settingsPane"
    static let panes = [("general", "General", "gearshape"), ("writing", "Writing", "pencil.line"),
                        ("animation", "Animation", "sparkles"), ("try", "Try It", "text.cursor")]

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let id = tabViewItem?.identifier as? String { UserDefaults.standard.set(id, forKey: Self.lastKey) }
    }
}

final class QuietWindow: NSWindow {
    override func noResponder(for eventSelector: Selector) {}

    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            self.window?.contentViewController = nil
            self.window = nil
        }
    }

    func show() {
        if window == nil {
            let tabs = SettingsTabs()
            tabs.tabStyle = .toolbar
            tabs.transitionOptions = []
            let panes = SettingsTabs.panes
            for (id, title, symbol) in panes {
                let host = NSHostingController(rootView: SettingsView(tab: id).environmentObject(Store.shared))
                host.sizingOptions = [.preferredContentSize]
                let item = NSTabViewItem(viewController: host)
                item.label = title
                host.title = "\(Identity.appName) — \(title)"
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                item.identifier = id
                tabs.addTabViewItem(item)
            }
            let start = CommandLine.arguments.first { $0.hasPrefix("--tab=") }.map { String($0.dropFirst(6)) }
                ?? UserDefaults.standard.string(forKey: SettingsTabs.lastKey) ?? "general"
            let w = QuietWindow(contentViewController: tabs)
            tabs.selectedTabViewItemIndex = panes.firstIndex { $0.0 == start } ?? 0
            w.styleMask = [.titled, .closable]
            w.toolbarStyle = .preference
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.window?.makeFirstResponder(nil) }
    }

    func peek() {
        show()
        NSApp.deactivate()
        window?.orderFrontRegardless()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launchedInBackground: Bool {
        if CommandLine.arguments.contains("--background") { return true }
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event?.paramDescriptor(forKeyword: 0x7072_6474)?.enumCodeValue == 0x6C67_6974 { return true }
        let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.launchDate
        return dock.map { Date().timeIntervalSince($0) < 120 } ?? false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Updates.shared.start()
        StatusBar.shared.setVisible(Store.shared.config.showInMenuBar)
        if CommandLine.arguments.contains("--peek") {
            SettingsWindow.shared.peek()
        } else if TidySetup.shouldOfferSetup(fresh: FirstLaunch.fresh, background: launchedInBackground) {
            SetupWindow.shared.show()
        } else if CommandLine.arguments.contains("--settings") || (!Store.shared.config.showInMenuBar && !launchedInBackground) {
            SettingsWindow.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return false
    }
}

final class StatusBar: NSObject, NSMenuDelegate {
    static let shared = StatusBar()
    private var item: NSStatusItem?

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image: NSImage? = featherTemplate()
            image?.isTemplate = true
            i.button?.image = image
            let menu = NSMenu()
            menu.delegate = self
            i.menu = menu
            item = i
        } else if !visible, let i = item {
            NSStatusBar.system.removeStatusItem(i)
            item = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let config = Store.shared.config
        addGroup(menu, title: "Style", options: styles, selected: config.style, action: #selector(pickStyle(_:)))
        menu.addItem(.separator())
        addGroup(menu, title: "Model", options: models, selected: config.model, action: #selector(pickModel(_:)))
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "Select text anywhere, press \(hotkeyName(config.hotkey))", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Set Up \(Identity.appName)…", #selector(openSetup)))
        menu.addItem(item("Check for Updates…", #selector(checkUpdates)))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(Identity.appName)", #selector(quit), key: "q"))
    }

    private func addGroup(_ menu: NSMenu, title: String, options: [Option], selected: String, action: Selector) {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for o in options {
            let mi = item(o.name, action)
            mi.representedObject = o.id
            mi.state = o.id == selected ? .on : .off
            menu.addItem(mi)
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func pickStyle(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { Store.shared.config.style = id }
    }

    @objc private func pickModel(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { Store.shared.config.model = id }
    }

    @objc private func openSettings() { SettingsWindow.shared.show() }

    @objc private func openSetup() { MainActor.assumeIsolated { SetupWindow.shared.show() } }

    @objc private func checkUpdates() { Updates.shared.checkNow() }

    @objc private func quit() { NSApp.terminate(nil) }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

@main
struct TidyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        let args = CommandLine.arguments
        guard let flag = args.dropFirst().first(where: { $0.hasPrefix("--login") }) else {
            let me = ProcessInfo.processInfo.processIdentifier
            if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Identity.bundleId)
                .first(where: { $0.processIdentifier != me && !$0.isTerminated }) {
                other.activate()
                exit(0)
            }
            FirstLaunch.fresh = !FileManager.default.fileExists(atPath: Paths.config.path)
            HUDController.shared.listen()
            HotKey.shared.onPress = { Fixer.shared.trigger() }
            HotKey.shared.register(Store.shared.config.hotkey)
            return
        }
        do {
            switch flag {
            case "--login-on": try SMAppService.mainApp.register()
            case "--login-off": try SMAppService.mainApp.unregister()
            default: break
            }
            let s = SMAppService.mainApp.status
            print(s == .enabled ? "enabled" : s == .requiresApproval ? "requiresApproval" : s == .notRegistered ? "notRegistered" : "notFound")
            exit(0)
        } catch {
            print("error: \(error.localizedDescription)")
            exit(1)
        }
    }

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { SettingsWindow.shared.show() }
                        .keyboardShortcut(",", modifiers: .command)
                    Button("Set Up \(Identity.appName)…") { SetupWindow.shared.show() }
                    Button("Check for Updates…") { Updates.shared.checkNow() }
                }
                CommandGroup(before: .windowSize) {
                    Button("Close") { NSApp.keyWindow?.performClose(nil) }
                        .keyboardShortcut("w", modifiers: .command)
                    Divider()
                }
                CommandGroup(replacing: .sidebar) {}
                CommandGroup(replacing: .toolbar) {}
                CommandGroup(replacing: .help) {}
            }
    }
}

final class SettingsUI: ObservableObject {
    nonisolated(unsafe) static var runSetup: () -> Void = {
        MainActor.assumeIsolated { SetupWindow.shared.show() }
    }
    static let shared = SettingsUI()
    @Published var tab = CommandLine.arguments.first { $0.hasPrefix("--tab=") }.map { String($0.dropFirst(6)) } ?? "settings"
    @Published var input = "hey how are u going, did u saw my mesage? i think its broke the export again"
    @Published var output = ""
    @Published var failed = false
    @Published var busy = false
    @Published var engine = ""
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError = ""

    func fix() {
        busy = true
        output = ""
        engine = ""
        let text = input
        Task { @MainActor in
            let r = await runFix(text)
            self.output = r.text
            self.failed = !r.ok
            self.engine = r.engine
            self.busy = false
        }
    }

    func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = ""
        } catch {
            loginError = error.localizedDescription
        }
    }
}

struct SettingsView: View {
    let tab: String
    @EnvironmentObject var store: Store
    @ObservedObject private var ui = SettingsUI.shared

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case "writing": writingTab
                case "animation": animationTab
                case "try": tryTab
                default: generalTab
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            Text(appVersion)
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .controlSize(.small)
        .frame(width: 480, height: 580)
    }

    private var writingTab: some View {
        Form {
            Section {
                Picker("Style", selection: $store.config.style) {
                    ForEach(styles) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
                Picker("Model", selection: $store.config.model) {
                    ForEach(models) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
                ModelDetailsRow(model: store.config.model)
                    .probe("writing.details")
                if store.config.model != "local" {
                    FallbackRow(on: Binding(
                        get: { store.config.fallbackLocal },
                        set: { v in withAnimation(.easeInOut(duration: 0.25)) { store.config.fallbackLocal = v } }))
                }
            } footer: {
                Text(blurb(styles, store.config.style))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LongTextField(title: "Vocabulary", hint: "Words to keep exactly as written.",
                              prompt: "Apple, Mac, Supercalifragilisticexpialidocious", text: $store.config.vocabulary)
                LongTextField(title: "Extra", hint: "Added to every fix.",
                              prompt: "e.g. Use British spelling", text: $store.config.extra)
            }
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section {
                LabeledContent("Accessibility") { AccessBadge() }
                LabeledContent {
                    ShortcutRecorder(shortcut: store.hotkeyBinding, defaultShortcut: hotkeyShortcut(defaultHotkey),
                                     conflicts: SiblingShortcuts.read(excluding: Identity.configDirName))
                } label: {
                    Text("Hotkey")
                    Text("Select text anywhere, then press it.")
                }
                .probe("general.hotkey")
                Toggle("Keep result in clipboard", isOn: $store.config.copyToClipboard)
            }
            Section {
                Toggle(isOn: $store.config.showInMenuBar) {
                    Text("Show in menu bar")
                    Text("When hidden, open \(Identity.appName) from Spotlight.")
                }
                Toggle("Open at login", isOn: $ui.openAtLogin)
                    .onChange(of: ui.openAtLogin) { _, on in ui.setLogin(on) }
                if !ui.loginError.isEmpty {
                    Text(ui.loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("First-launch setup") {
                    Button("Run Setup Again") { SettingsUI.runSetup() }
                        .help("Open first-launch setup. Your current settings are kept.")
                }
            }
            UpdatesSection()
        }
        .formStyle(.grouped)
    }

    private var animationTab: some View {
        Form {
            Section {
                Picker("Size", selection: Binding(
                    get: { store.config.hudSize },
                    set: { v in withAnimation(.easeInOut(duration: 0.25)) { store.config.hudSize = v } })) {
                    ForEach(hudSizes) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .probe("anim.size")
            } footer: {
                Text(store.config.hudSize == "off" ? "Off: no bubble, the text just changes." : "Shown right above the text you're fixing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let scale = HUDController.scale(for: store.config.hudSize) {
                Section {
                    ZStack {
                        LinearGradient(colors: [Color(white: 0.42), Color(white: 0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        HUDPreview(scale: scale, orb: OrbState(rawValue: store.config.orbState) ?? .composing,
                                   showText: store.config.hudText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Text("Real size")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.black.opacity(0.3), in: Capsule())
                            .padding(8)
                    }
                    .probe("anim.preview")
                    Picker("Orb", selection: $store.config.orbState) {
                        ForEach(orbChoices, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .probe("anim.orb")
                    Toggle("Show text", isOn: $store.config.hudText)
                        .probe("anim.text")
                }
                .transition(.opacity)
            }
        }
        .formStyle(.grouped)
    }

    private var tryTab: some View {
        Form {
            Section {
                TextField("Text", text: $ui.input, axis: .vertical)
                    .lineLimit(3...5)
                    .labelsHidden()
                HStack {
                    Text("\(styles.first { $0.id == store.config.style }?.name ?? "") · \(models.first { $0.id == store.config.model }?.name ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if ui.busy {
                        ThinkingOrb(state: OrbState(rawValue: store.config.orbState) ?? .composing, size: .px20, displaySize: 18)
                    }
                    Button("Fix") { ui.fix() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(ui.busy || ui.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if !ui.output.isEmpty {
                Section {
                    Text(ui.output)
                        .textSelection(.enabled)
                        .foregroundStyle(ui.failed ? .red : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(6)
                    HStack {
                        if !ui.engine.isEmpty {
                            Text(ui.engine == "local" ? "Apple on-device model" : ui.engine)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !ui.failed {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(ui.output, forType: .string)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func blurb(_ list: [Option], _ id: String) -> String {
        list.first { $0.id == id }?.blurb ?? ""
    }
}

func runTool(_ url: URL, _ args: [String]) -> String? {
    guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
    let p = Process()
    p.executableURL = url
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardInput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

final class ModelStatus: ObservableObject {
    static let shared = ModelStatus()

    enum Claude: Equatable { case checking, connected(String), notSignedIn, notInstalled }

    @Published var claude: Claude = .checking
    @Published var local: [String: String] = [:]

    private let claudePaths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                               Paths.home.appendingPathComponent(".local/bin/claude").path]

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let claudeURL = self.claudePaths.map(URL.init(fileURLWithPath:))
                .first { FileManager.default.isExecutableFile(atPath: $0.path) }
            var claude: Claude = .notInstalled
            if let claudeURL, let json = runTool(claudeURL, ["auth", "status"]),
               let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
                if obj["loggedIn"] as? Bool == true {
                    let who = [obj["email"] as? String, (obj["orgName"] as? String).map { "(\($0))" }]
                        .compactMap { $0 }.joined(separator: " ")
                    claude = .connected(who)
                } else {
                    claude = .notSignedIn
                }
            } else if claudeURL != nil {
                claude = .notSignedIn
            }

            var local: [String: String] = ["status": "missing"]
            if let text = runTool(Paths.localHelper, ["--info"]) {
                local = [:]
                for line in text.split(separator: "\n") {
                    let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
                    if kv.count == 2 { local[kv[0]] = kv[1] }
                }
            }
            DispatchQueue.main.async {
                self.claude = claude
                self.local = local
            }
        }
    }

    var localReady: Bool { local["status"] == "ready" }
}

func featherTemplate(size: CGFloat = 18) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
        let right = NSBezierPath()
        right.move(to: NSPoint(x: 0, y: -436))
        right.curve(to: NSPoint(x: 184, y: 4), controlPoint1: NSPoint(x: 130, y: -350), controlPoint2: NSPoint(x: 194, y: -160))
        right.curve(to: NSPoint(x: 22, y: 300), controlPoint1: NSPoint(x: 174, y: 150), controlPoint2: NSPoint(x: 106, y: 254))
        right.line(to: NSPoint(x: 16, y: 300))
        right.curve(to: NSPoint(x: 8, y: -374), controlPoint1: NSPoint(x: 15, y: 100), controlPoint2: NSPoint(x: 12, y: -200))
        right.close()
        let left = NSBezierPath()
        left.move(to: NSPoint(x: -8, y: -374))
        left.curve(to: NSPoint(x: -16, y: 300), controlPoint1: NSPoint(x: -12, y: -200), controlPoint2: NSPoint(x: -15, y: 100))
        left.line(to: NSPoint(x: -22, y: 300))
        left.curve(to: NSPoint(x: -136, y: 192), controlPoint1: NSPoint(x: -78, y: 278), controlPoint2: NSPoint(x: -116, y: 238))
        left.line(to: NSPoint(x: -98, y: 176))
        left.curve(to: NSPoint(x: -170, y: -56), controlPoint1: NSPoint(x: -152, y: 130), controlPoint2: NSPoint(x: -172, y: 46))
        left.curve(to: NSPoint(x: -8, y: -374), controlPoint1: NSPoint(x: -168, y: -210), controlPoint2: NSPoint(x: -96, y: -322))
        left.close()
        let quill = NSBezierPath()
        quill.move(to: NSPoint(x: -26, y: 290))
        quill.line(to: NSPoint(x: 26, y: 290))
        quill.line(to: NSPoint(x: 8, y: 450))
        quill.line(to: NSPoint(x: -8, y: 450))
        quill.close()
        let t = NSAffineTransform()
        t.translateX(by: size / 2, yBy: size / 2)
        t.rotate(byDegrees: 40)
        t.scale(by: size / 930)
        t.translateX(by: 0, yBy: 7)
        for p in [right, left, quill] {
            p.transform(using: t as AffineTransform)
            NSColor.black.setFill()
            p.fill()
        }
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = Identity.appName
    return image
}

let orbChoices: [OrbState] = [.composing, .breathing, .weaving, .listening]

var appVersion: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? "?"
    let build = info["CFBundleVersion"] as? String ?? "?"
    return "\(Identity.appName) \(version) (\(build))"
}

struct LongTextField: View {
    let title: String
    let hint: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            field
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var field: some View {
        let base = TextField(title, text: $text, prompt: Text(prompt), axis: .vertical)
            .labelsHidden()
            .lineLimit(3...6)
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            base.textFieldStyle(.bordered)
        } else {
            base.textFieldStyle(.roundedBorder)
        }
        #else
        base.textFieldStyle(.roundedBorder)
        #endif
    }
}

struct StatusLine: View {
    let ok: Bool?
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: ok == nil ? "clock.fill" : ok! ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok == nil ? .secondary : ok! ? Color.green : Color.orange)
        }
        .font(.caption)
    }
}

struct ModelDetailsRow: View {
    let model: String
    @ObservedObject private var status = ModelStatus.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if model == "local" { localDetails } else { haikuDetails }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { status.refresh() }
    }

    @ViewBuilder private var haikuDetails: some View {
        switch status.claude {
        case .checking: StatusLine(ok: nil, text: "Checking connection…")
        case .connected(let who): StatusLine(ok: true, text: "Connected as \(who)")
        case .notSignedIn: StatusLine(ok: false, text: "Not signed in — run `claude` in Terminal and log in")
        case .notInstalled: StatusLine(ok: false, text: "Claude Code not installed — get it at claude.com/claude-code")
        }
        Text("Cloud · ~3 s · uses your Claude plan")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var localDetails: some View {
        localStatus
        if status.localReady {
            let weak = keyboardLanguages.filter { !$0.supported }.map(\.name)
            if !weak.isEmpty {
                Label("\(weak.joined(separator: ", ")): not officially supported, may be weaker", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var keyboardLanguages: [(name: String, supported: Bool)] {
        (status.local["keyboard"] ?? "").split(separator: ",").compactMap { item in
            let parts = item.split(separator: ":").map(String.init)
            return parts.count == 2 ? (parts[0], parts[1] == "yes") : nil
        }
    }

    @ViewBuilder var localStatus: some View {
        switch status.local["status"] {
        case nil: StatusLine(ok: nil, text: "Checking…")
        case "ready": StatusLine(ok: true, text: "On-device · offline · free")
        case "notEnabled":
            HStack {
                StatusLine(ok: false, text: "Needs setup: turn on Apple Intelligence")
                Spacer()
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
                }
            }
        case "notReady": StatusLine(ok: nil, text: "Model is still downloading — try again later")
        case "notEligible": StatusLine(ok: false, text: "This Mac can't run Apple's on-device model")
        case "missing": StatusLine(ok: false, text: "Helper not built — run build.sh")
        default: StatusLine(ok: false, text: "Unavailable: \(status.local["status"] ?? "")")
        }
    }
}

struct FallbackRow: View {
    @Binding var on: Bool
    @ObservedObject private var status = ModelStatus.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle("Use local model if Claude fails", isOn: $on)
                .probe("writing.fallback")
            if on {
                ModelDetailsRow(model: "local").localStatus
                    .probe("writing.fallbackStatus")
                    .transition(.opacity)
            }
        }
    }
}

struct AccessBadge: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if Access.trusted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow Accessibility") {
                    Access.request()
                    Access.openSettings()
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
            }
        }
    }
}
