import AppKit
import ApplicationServices
import Carbon.HIToolbox

let hotkeys = [
    Option(id: "ctrl-opt-f", name: "⌃⌥F", blurb: ""),
    Option(id: "ctrl-opt-r", name: "⌃⌥R", blurb: ""),
    Option(id: "ctrl-opt-space", name: "⌃⌥Space", blurb: ""),
    Option(id: "ctrl-shift-f", name: "⌃⇧F", blurb: ""),
]

func hotkeyName(_ id: String) -> String {
    hotkeys.first { $0.id == id }?.name ?? "⌃⌥F"
}

final class HotKey {
    static let shared = HotKey()

    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    func register(_ id: String) {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let (code, mods): (Int, Int) = switch id {
        case "ctrl-opt-r": (kVK_ANSI_R, controlKey | optionKey)
        case "ctrl-opt-space": (kVK_Space, controlKey | optionKey)
        case "ctrl-shift-f": (kVK_ANSI_F, controlKey | shiftKey)
        default: (kVK_ANSI_F, controlKey | optionKey)
        }
        let hotID = EventHotKeyID(signature: OSType(0x4658_5458), id: 1)
        RegisterEventHotKey(UInt32(code), UInt32(mods), hotID, GetApplicationEventTarget(), 0, &ref)
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

enum TextLocator {
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

    private static func frame(_ el: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &size) == .success,
              let pos, let size else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    private static func toCocoa(_ r: CGRect) -> CGRect? {
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

    static func waitForModifiersUp(timeout: Double = 0.8, then: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            let f = CGEventSource.flagsState(.combinedSessionState)
            let held = f.contains(.maskControl) || f.contains(.maskAlternate) || f.contains(.maskShift) || f.contains(.maskCommand)
            if !held || Date() > deadline { then() } else {
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
        guard !running else { return }
        guard Access.trusted else {
            Access.request()
            HUDController.shared.flash(.failed("Allow Accessibility first"), anchor: nil)
            return
        }
        running = true
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focus = TextLocator.focusedElement()
        let anchor = TextLocator.selectionRect()
        let config = Store.shared.config

        Keys.waitForModifiersUp {
            let pb = NSPasteboard.general
            let saved = Clip.save(pb)
            let before = pb.changeCount
            Keys.cmd(CGKeyCode(kVK_ANSI_C))
            self.waitForCopy(pb, from: before, until: Date().addingTimeInterval(0.6)) { copied in
                guard copied, let text = pb.string(forType: .string),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    Clip.restore(saved, pb)
                    HUDController.shared.flash(.failed("Select some text first"), anchor: anchor)
                    self.running = false
                    return
                }
                Clip.write(text, pb)
                HUDController.shared.show(label: "Thinking", anchor: anchor)
                Task { @MainActor in
                    let r = await runFix(text)
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
            HUDController.shared.finish(.done("Copied — field changed"))
            running = false
            return
        }
        Keys.cmd(CGKeyCode(kVK_ANSI_V))
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
