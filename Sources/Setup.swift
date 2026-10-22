import AppKit
import SwiftUI

enum TidySetup {
    static func shouldOfferSetup(fresh: Bool, background: Bool) -> Bool { fresh && !background }

    static let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static let sample = "hey how are u going, did u saw my mesage? i think its broke the export again"
}

@MainActor
final class SetupModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, access, model, style, tryIt }

    @Published var step = 0
    @Published var forward = true
    @Published var celebrating = false
    @Published var trusted = false
    @Published var input = TidySetup.sample
    @Published var output = ""
    @Published var failed = false
    @Published var busy = false
    @Published var frames = SetupFrames()
    var readTrusted: () -> Bool = { Access.trusted }
    var requestAccess: () -> Void = {
        Access.request()
        NSWorkspace.shared.open(TidySetup.accessibilityURL)
    }
    var fixer: (String) async -> (ok: Bool, text: String, engine: String) = { await runFix($0) }
    var onFinish: () -> Void = {}
    private var timer: Timer?
    private(set) var requested = 0

    static let count = Step.allCases.count

    var current: Step { Step(rawValue: step) ?? .welcome }
    var isWatching: Bool { timer != nil }

    func reset() {
        step = 0
        forward = true
        celebrating = false
        input = TidySetup.sample
        output = ""
        failed = false
        trusted = readTrusted()
    }

    func page(_ s: Int) -> SetupPage {
        let name = Identity.appName
        switch Step(rawValue: s) ?? .welcome {
        case .welcome:
            return SetupPage(title: "Welcome to \(name)", subtitle: "Select text anywhere, press a hotkey, and get it back fixed.",
                             primary: "Get Started")
        case .access:
            return SetupPage(title: "Allow Accessibility",
                             subtitle: "\(name) needs it to copy your selection and paste the fixed text back.",
                             primary: trusted ? "Continue" : "Allow Accessibility", back: true,
                             link: trusted ? nil : "Skip for now")
        case .model:
            return SetupPage(title: "Choose how text is fixed",
                             subtitle: "Local runs on this Mac. Haiku is smarter and uses your Claude account.",
                             primary: "Continue", back: true)
        case .style:
            return SetupPage(title: "Your style and hotkey", subtitle: "You can change both any time in Settings.",
                             primary: "Continue", back: true)
        case .tryIt:
            return SetupPage(title: "Try it", subtitle: "Fix this sample, or type your own.",
                             primary: "Finish", back: true)
        }
    }

    func refresh() {
        if current == .access { trusted = readTrusted() }
    }

    func stepChanged() {
        stopWatching()
        refresh()
        if current == .access { startWatching() }
    }

    func startWatching() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    func primary() {
        switch current {
        case .access where !trusted:
            requested += 1
            requestAccess()
        case .tryIt:
            finish()
        default:
            go(1)
        }
    }

    func link() { go(1) }

    func go(_ delta: Int) {
        forward = delta > 0
        step = max(0, min(Self.count - 1, step + delta))
        stepChanged()
    }

    func fix() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        busy = true
        output = ""
        Task { @MainActor in
            let r = await fixer(text)
            output = r.text
            failed = !r.ok
            busy = false
        }
    }

    func finish() {
        stopWatching()
        celebrating = true
        onFinish()
    }
}

struct SetupView: View {
    @ObservedObject var m: SetupModel
    @ObservedObject var store: Store
    @ObservedObject private var hotkeyStatus = HotKeyStatus.shared
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SetupScaffold(step: m.step, count: SetupModel.count, forward: m.forward, celebrating: m.celebrating,
                      page: { m.page($0) },
                      onPrimary: primary, onBack: { m.go(-1) }, onLink: { m.link() },
                      report: { m.frames.set($0, $1) }) { s in
            switch SetupModel.Step(rawValue: s) ?? .welcome {
            case .welcome: welcomeContent
            case .access: accessContent
            case .model: modelContent
            case .style: styleContent
            case .tryIt: tryContent
            }
        }
        .ignoresSafeArea()
    }

    private func primary() {
        let finishing = m.current == .tryIt
        m.primary()
        if finishing {
            DispatchQueue.main.asyncAfter(deadline: .now() + SetupHost.celebrationDuration(reduceMotion: reduceMotion)) { close() }
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            ZStack {
                LinearGradient(colors: [Color(white: 0.42), Color(white: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 14) {
                    Text("hey how are u going")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .strikethrough(true, color: .white.opacity(0.4))
                    HUDPreview(scale: 0.8, orb: OrbState(rawValue: store.config.orbState) ?? .composing)
                    Text("Hey, how are you going?")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 176)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Works in any app: mail, chat, notes, the browser.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var accessContent: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            if m.trusted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
                Text("Accessibility is allowed").font(.headline)
            } else {
                Image(systemName: "hand.raised.circle")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.secondary)
                Text("System Settings opens on Accessibility. Turn on \(Identity.appName), then come back here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: m.trusted)
    }

    private var modelContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            Picker("", selection: $store.config.model) {
                ForEach(models) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            SetupBox {
                ModelDetailsRow(model: store.config.model)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(models.first { $0.id == store.config.model }?.blurb ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var styleContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                Text("Style").font(.headline)
                Picker("", selection: $store.config.style) {
                    ForEach(styles) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
                Text(styles.first { $0.id == store.config.style }?.blurb ?? "")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Hotkey").font(.headline)
                ShortcutRecorder(shortcut: store.hotkeyBinding, defaultShortcut: hotkeyShortcut(defaultHotkey),
                                 conflicts: SiblingShortcuts.read(excluding: Identity.configDirName),
                                 problem: hotkeyStatus.problem)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Select text anywhere, then press it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var tryContent: some View {
        VStack(spacing: 10) {
            SetupBox {
                TextField("Type something to fix", text: $m.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            HStack {
                Text("\(styles.first { $0.id == store.config.style }?.name ?? "") · \(models.first { $0.id == store.config.model }?.name ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if m.busy { ProgressView().controlSize(.small) }
                Button("Fix") { m.fix() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(m.busy || m.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            SetupBox {
                Text(m.output.isEmpty ? "The fixed text appears here." : m.output)
                    .foregroundStyle(m.output.isEmpty ? AnyShapeStyle(.secondary) : (m.failed ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary)))
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

@MainActor
final class SetupWindow: NSObject, NSWindowDelegate {
    static let shared = SetupWindow()
    private let model = SetupModel()
    private var window: NSWindow?

    func show() {
        model.reset()
        if window == nil {
            window = SetupHost.makeWindow(SetupView(m: model, store: Store.shared) { [weak self] in self?.window?.close() },
                                          delegate: self)
        }
        model.stepChanged()
        SetupHost.bringToFront(window)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopWatching()
    }
}
