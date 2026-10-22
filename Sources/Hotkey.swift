import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

let fixLog = Logger(subsystem: Identity.bundleId, category: "fix")

let defaultHotkey = "ctrl-opt-f"

func hotkeyShortcut(_ id: String) -> RecordedShortcut? { ShortcutRules.parse(id) }

func hotkeyName(_ id: String) -> String {
    hotkeyShortcut(id)?.display ?? "Off"
}

func normalizedHotkey(_ id: String) -> String {
    if id == "off" { return id }
    return hotkeyShortcut(id)?.storageID ?? id
}

final class HotKeyStatus: ObservableObject {
    static let shared = HotKeyStatus()
    @Published var problem: String?
}

enum HotKeyProblem {
    static func message(status: OSStatus, shortcut: RecordedShortcut?,
                        macOS: [(RecordedShortcut, String)] = MacShortcuts.enabled) -> String? {
        guard let shortcut else { return nil }
        if status != noErr { return "Couldn't use \(shortcut.display) (error \(status)). Pick another shortcut." }
        if let hit = macOS.first(where: { $0.0 == shortcut }) {
            return "macOS uses \(shortcut.display) for \(hit.1). Pick another shortcut."
        }
        return nil
    }
}

final class HotKey {
    static let shared = HotKey()

    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false
    private(set) var lastStatus: OSStatus = noErr
    private(set) var registered: RecordedShortcut?

    func register(_ id: String) {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        guard let shortcut = hotkeyShortcut(id) else {
            fixLog.log("hotkey off (id \(id, privacy: .public))")
            lastStatus = noErr
            registered = nil
            publish(nil)
            return
        }
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                fixLog.log("hotkey pressed")
                DispatchQueue.main.async { HotKey.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, nil)
            fixLog.log("hotkey handler installed: \(installed)")
            handlerInstalled = installed == noErr
        }
        let hotID = EventHotKeyID(signature: OSType(0x4658_5458), id: 1)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.carbonModifiers), hotID,
                                         GetApplicationEventTarget(), 0, &ref)
        lastStatus = status
        registered = status == noErr ? shortcut : nil
        fixLog.log("hotkey register \(shortcut.display, privacy: .public) keyCode \(shortcut.keyCode) carbon \(shortcut.carbonModifiers) status \(status) trusted \(Access.trusted)")
        publish(HotKeyProblem.message(status: status, shortcut: shortcut))
    }

    private func publish(_ problem: String?) {
        if Thread.isMainThread { HotKeyStatus.shared.problem = problem } else {
            DispatchQueue.main.async { HotKeyStatus.shared.problem = problem }
        }
    }
}

enum Access {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func request() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

enum ModifierWait {
    static func held(_ f: CGEventFlags) -> Bool {
        f.contains(.maskControl) || f.contains(.maskAlternate) || f.contains(.maskShift) || f.contains(.maskCommand)
    }
}

enum TextLocator {
    static func selectedText(_ element: AXUIElement?) -> String? {
        guard let element else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    static func windowFrame(_ element: AXUIElement?) -> CGRect? {
        guard let element else { return nil }
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &win) == .success,
              let win, CFGetTypeID(win) == AXUIElementGetTypeID() else { return nil }
        return frame(win as! AXUIElement).flatMap(toCocoa)
    }

    static func target() -> (anchor: CGRect?, window: CGRect?) {
        guard Access.trusted else { return (nil, nil) }
        let window = windowFrame(focusedElement())
        return (HUDPlacement.validAnchor(selectionRect(), window: window), window)
    }

    static func focusedElement() -> AXUIElement? {
        guard Access.trusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func selectionRect() -> CGRect? {
        guard Access.trusted else { return nil }
        if let app = NSWorkspace.shared.frontmostApplication {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement

        if let r = selectionBounds(element).flatMap(toCocoa) { return r }
        if let r = frame(element), r.height < 400, let c = toCocoa(r) { return c }
        return nil
    }

    private static func selectionBounds(_ el: AXUIElement) -> CGRect? {
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            el, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else { return nil }
        guard rect.height > 0, rect.height < 2000, rect.width < 5000 else { return nil }
        return rect
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &size) == .success,
              let pos, let size else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func toCocoa(_ r: CGRect) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let c = CGRect(x: r.minX, y: primary.frame.height - r.maxY, width: r.width, height: r.height)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(c.insetBy(dx: -1, dy: -1)) }) else { return nil }
        return c
    }
}

enum Clip {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    @discardableResult
    static func write(_ text: String, _ pb: NSPasteboard) -> Int {
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transient)
        item.setData(Data(), forType: concealed)
        pb.writeObjects([item])
        return pb.changeCount
    }

    static func save(_ pb: NSPasteboard) -> Snapshot {
        (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
            return d
        }
    }

    static func restore(_ snap: Snapshot, _ pb: NSPasteboard) {
        pb.clearContents()
        let items = snap.map { d -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, v) in d { item.setData(v, forType: t) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }
}

enum Keys {
    static func cmd(_ key: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
    }

    static func waitForModifiersUp(timeout: Double = 1.5, then: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            let held = ModifierWait.held(CGEventSource.flagsState(.combinedSessionState))
            if !held || Date() > deadline {
                if held { fixLog.log("modifiers still held after \(timeout)s") }
                then()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: poll)
            }
        }
        poll()
    }
}

final class Fixer {
    static let shared = Fixer()
    private var running = false

    func trigger() {
        let trusted = Access.trusted
        fixLog.log("trigger: running \(self.running) trusted \(trusted) front \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-", privacy: .public)")
        guard !running else { return }
        guard trusted else {
            Access.request()
            HUDController.shared.flash(.failed("Allow Accessibility first"), anchor: nil)
            return
        }
        running = true
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focus = TextLocator.focusedElement()
        let place = TextLocator.target()
        let anchor = place.anchor
        let window = place.window
        let config = Store.shared.config
        let axText = TextLocator.selectedText(focus)
        fixLog.log("selection via AX: \(axText?.count ?? -1) chars, anchor \(anchor != nil), window \(window != nil)")

        Keys.waitForModifiersUp {
            let pb = NSPasteboard.general
            let saved = Clip.save(pb)
            let before = pb.changeCount
            Keys.cmd(CGKeyCode(kVK_ANSI_C))
            self.waitForCopy(pb, from: before, until: Date().addingTimeInterval(1.0)) { copied in
                let copiedText = copied ? pb.string(forType: .string) : nil
                fixLog.log("copy: changeCount \(before) → \(pb.changeCount) copied \(copied) length \(copiedText?.count ?? -1)")
                let usable = { (t: String?) -> String? in
                    guard let t, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    return t
                }
                guard let text = usable(copiedText) ?? usable(axText) else {
                    Clip.restore(saved, pb)
                    fixLog.log("no selection found")
                    HUDController.shared.flash(.failed("Select some text first"), anchor: anchor, window: window)
                    self.running = false
                    return
                }
                Clip.write(text, pb)
                HUDController.shared.show(label: "Thinking", anchor: anchor, window: window)
                let started = Date()
                Task { @MainActor in
                    let r = await runFix(text)
                    fixLog.log("fixer: ok \(r.ok) engine \(r.engine, privacy: .public) \(Int(Date().timeIntervalSince(started) * 1000)) ms")
                    self.finish(r, text: text, saved: saved, front: front, focus: focus, config: config)
                }
            }
        }
    }

    private func waitForCopy(_ pb: NSPasteboard, from count: Int, until: Date, done: @escaping (Bool) -> Void) {
        if pb.changeCount != count { return done(true) }
        if Date() > until { return done(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            self.waitForCopy(pb, from: count, until: until, done: done)
        }
    }

    private func finish(_ r: (ok: Bool, text: String, engine: String), text: String,
                        saved: Clip.Snapshot, front: pid_t?, focus: AXUIElement?, config: Config) {
        let pb = NSPasteboard.general
        guard r.ok, !r.text.isEmpty else {
            Clip.restore(saved, pb)
            HUDController.shared.finish(.failed(r.text == "Timed out" ? "Timed out" : "Couldn't fix"))
            running = false
            return
        }
        let frontApp = NSWorkspace.shared.frontmostApplication
        let result = Self.terminals.contains(frontApp?.bundleIdentifier ?? "") ? Self.terminalSafe(r.text) : r.text
        let ours = Clip.write(result, pb)

        guard frontApp?.processIdentifier == front else {
            fixLog.log("not pasted: app changed")
            HUDController.shared.finish(.done("Copied — app changed"))
            running = false
            return
        }
        let now = TextLocator.focusedElement()
        let sameField: Bool = switch (focus, now) {
        case (nil, nil): true
        case let (a?, b?): CFEqual(a, b)
        default: false
        }
        guard sameField else {
            fixLog.log("not pasted: field changed")
            HUDController.shared.finish(.done("Copied — field changed"))
            running = false
            return
        }
        Keys.cmd(CGKeyCode(kVK_ANSI_V))
        fixLog.log("pasted")
        let label = (r.engine == "local" && config.model != "local") ? "Done · local model" : "Done"
        HUDController.shared.finish(.done(label))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if !config.copyToClipboard, pb.changeCount == ours { Clip.restore(saved, pb) }
            self.running = false
        }
    }

    static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm",
    ]

    static func terminalSafe(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let kept = normalized.unicodeScalars.filter { u in
            if u == "\n" || u == "\t" { return true }
            if u.value < 0x20 || u.value == 0x7f { return false }
            if (0x80...0x9f).contains(u.value) { return false }
            return true
        }
        var out = String(String.UnicodeScalarView(kept))
        while let last = out.last, last.isNewline || last == " " || last == "\t" { out.removeLast() }
        return out
    }
}
