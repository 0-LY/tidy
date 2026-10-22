import AppKit
import SwiftUI

enum HUDPhase: Equatable {
    case hidden
    case thinking
    case done(String)
    case failed(String)
}

final class HUDModel: ObservableObject {
    @Published var showText = true
    @Published var phase: HUDPhase = .hidden
    @Published var label = "Thinking"
    @Published var scale: CGFloat = 1
    @Published var orb: OrbState = .composing
}

final class HUDController {
    static let shared = HUDController()

    let model = HUDModel()
    private var panel: NSPanel?
    private var host: NSHostingView<HUDView>?
    private var pending: DispatchWorkItem?

    static func scale(for size: String) -> CGFloat? {
        switch size {
        case "off": return nil
        case "small": return 0.72
        case "large": return 1.4
        default: return 1
        }
    }

    func listen() {
        DistributedNotificationCenter.default().addObserver(
            forName: Identity.stateNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.handle(note.object as? String ?? "")
        }
    }

    private func handle(_ message: String) {
        let parts = message.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : nil
        switch parts.first {
        case "start":
            let place = TextLocator.target()
            show(label: arg ?? "Thinking", anchor: place.anchor, window: place.window)
        case "done": finish(.done(arg ?? "Done"))
        case "fail": finish(.failed(arg ?? "Couldn't fix"))
        default: break
        }
    }

    func show(label: String, anchor: CGRect?, window: CGRect? = nil) {
        let config = Store.shared.config
        guard let scale = Self.scale(for: config.hudSize) else { return }
        pending?.cancel()
        model.scale = scale
        model.orb = OrbState(rawValue: config.orbState) ?? .composing
        model.showText = config.hudText
        model.label = label
        let p = panel ?? makePanel()
        panel = p
        let size = host?.fittingSize ?? NSSize(width: 240 * scale, height: 70 * scale)
        p.setContentSize(size)
        host?.frame = NSRect(origin: .zero, size: size)
        place(p, size: size, anchor: anchor, window: window)
        p.orderFrontRegardless()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { model.phase = .thinking }
        schedule(after: 90) { [weak self] in self?.finish(.failed("Timed out")) }
    }

    func finish(_ phase: HUDPhase) {
        guard panel?.isVisible == true else { return }
        pending?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) { model.phase = phase }
        let isFail: Bool = if case .failed = phase { true } else { false }
        schedule(after: isFail ? 1.8 : 1.0) { [weak self] in self?.hide() }
    }

    func flash(_ phase: HUDPhase, anchor: CGRect?, window: CGRect? = nil) {
        show(label: "Thinking", anchor: anchor, window: window)
        finish(phase)
    }

    private func hide() {
        withAnimation(.easeIn(duration: 0.22)) { model.phase = .hidden }
        schedule(after: 0.3) { [weak self] in self?.panel?.orderOut(nil) }
    }

    private func schedule(after seconds: Double, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let h = NSHostingView(rootView: HUDView(model: model))
        p.contentView = h
        host = h
        return p
    }

    private func place(_ p: NSPanel, size: NSSize, anchor: CGRect?, window: CGRect?) {
        let screens = NSScreen.screens.map { (frame: $0.frame, visible: $0.visibleFrame) }
        p.setFrameOrigin(HUDPlacement.origin(size: size, anchor: anchor, window: window,
                                             mouse: NSEvent.mouseLocation, screens: screens))
    }
}

enum HUDPlacement {
    static func validAnchor(_ anchor: CGRect?, window: CGRect?) -> CGRect? {
        guard let anchor else { return nil }
        guard let window else { return anchor }
        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        return window.insetBy(dx: -24, dy: -24).contains(center) ? anchor : nil
    }

    static func screen(for point: NSPoint, screens: [(frame: CGRect, visible: CGRect)]) -> (frame: CGRect, visible: CGRect)? {
        if let hit = screens.first(where: { NSMouseInRect(point, $0.frame, false) }) { return hit }
        return screens.min { distance(point, $0.frame) < distance(point, $1.frame) }
    }

    private static func distance(_ p: NSPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }

    static func origin(size: NSSize, anchor: CGRect?, window: CGRect?, mouse: NSPoint,
                       screens: [(frame: CGRect, visible: CGRect)]) -> NSPoint {
        let point: NSPoint
        if let a = anchor { point = NSPoint(x: a.minX, y: a.midY) }
        else if let w = window { point = NSPoint(x: w.midX, y: w.midY) }
        else { point = mouse }
        let vis = screen(for: point, screens: screens)?.visible ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin: NSPoint
        if let a = anchor {
            origin = NSPoint(x: a.minX - 6, y: a.maxY + 2)
            if origin.y + size.height > vis.maxY { origin.y = a.minY - size.height - 2 }
        } else if let w = window, !w.contains(mouse) {
            origin = NSPoint(x: w.midX - size.width / 2, y: w.maxY - size.height - 56)
        } else {
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y + 16)
            if origin.y + size.height > vis.maxY { origin.y = mouse.y - size.height - 16 }
        }
        origin.x = min(max(origin.x, vis.minX + 4), vis.maxX - size.width - 4)
        origin.y = min(max(origin.y, vis.minY + 4), vis.maxY - size.height - 4)
        return origin
    }
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        let visible = model.phase != .hidden
        HUDPill(phase: model.phase == .hidden ? .thinking : model.phase, label: model.label, k: model.scale,
                orb: model.orb, paused: !visible, showText: model.showText)
            .scaleEffect(visible ? 1 : 0.82)
            .opacity(visible ? 1 : 0)
            .padding(6)
            .fixedSize()
    }
}

struct HUDPill: View {
    let phase: HUDPhase
    let label: String
    let k: CGFloat
    var orb: OrbState = .composing
    var paused = false
    var showText = true

    var body: some View {
        HStack(spacing: 12 * k) {
            ZStack {
                switch phase {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28 * k, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28 * k, weight: .semibold))
                        .foregroundStyle(.red)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                default:
                    ThinkingOrb(state: orb, size: .px64, paused: paused, displaySize: 38 * k)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: 38 * k, height: 38 * k)

            if showText {
            ZStack(alignment: .leading) {
                Text("\(label)....").opacity(0)
                switch phase {
                case .done(let text): Text(text).transition(.opacity)
                case .failed(let text): Text(text).transition(.opacity)
                default:
                    if paused { Text("\(label)...") } else { ThinkingLabel(text: label).transition(.opacity) }
                }
            }
            .font(.system(size: 16 * k, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            }
        }
        .padding(.leading, 10 * k)
        .padding(.trailing, (showText ? 20 : 10) * k)
        .padding(.vertical, 8 * k)
        .glassEffect(.regular, in: Capsule())
    }
}

struct HUDPreview: View {
    let scale: CGFloat
    var orb: OrbState = .composing
    var showText = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.2)
            let phase: HUDPhase = t < 3 ? .thinking : .done("Done")
            HUDPill(phase: phase, label: "Thinking", k: scale, orb: orb, showText: showText)
                .animation(.spring(response: 0.32, dampingFraction: 0.7), value: phase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

struct ThinkingLabel: View {
    let text: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let n = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 4 + 1
            let dots = String(repeating: ".", count: n)
            let pad = Text(String(repeating: ".", count: 4 - n)).foregroundColor(.clear)
            Text("\(text)\(dots)\(pad)")
        }
    }
}
