import AppKit

let args = CommandLine.arguments

if args.count > 3, args[1] == "--compose" {
    let canvas = 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let art = NSImage(contentsOfFile: args[2])!
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    art.draw(in: NSRect(x: 100, y: 100, width: 824, height: 824))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
    print(args[3])
    exit(0)
}
let out = args.count > 1 ? args[1] : "icon-1024.png"
let variant = args.count > 2 ? args[2] : "graphite"
let size = 1024

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func squircle(_ rect: NSRect, exponent n: CGFloat = 5) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
    }
    path.close()
    return path
}

struct Palette {
    let top: NSColor, bottom: NSColor
    let glyphTop: NSColor, glyphBottom: NSColor
    let glyphShadow: NSColor
    let rimLight: NSColor
}

let palettes: [String: Palette] = [
    "graphite": Palette(top: rgb(122, 125, 132), bottom: rgb(44, 46, 51),
                        glyphTop: rgb(255, 255, 255), glyphBottom: rgb(214, 216, 222),
                        glyphShadow: rgb(0, 0, 0, 0.35), rimLight: rgb(255, 255, 255, 0.22)),
    "silver": Palette(top: rgb(250, 250, 252), bottom: rgb(184, 188, 196),
                      glyphTop: rgb(92, 95, 102), glyphBottom: rgb(46, 48, 53),
                      glyphShadow: rgb(0, 0, 0, 0.18), rimLight: rgb(255, 255, 255, 0.9)),
]
let p = palettes[variant] ?? palettes["graphite"]!

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(body)

NSGraphicsContext.saveGraphicsState()
let drop = NSShadow()
drop.shadowColor = rgb(0, 0, 0, 0.30)
drop.shadowBlurRadius = 20
drop.shadowOffset = NSSize(width: 0, height: -10)
drop.set()
p.bottom.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(starting: p.top, ending: p.bottom)!.draw(in: shape, angle: -90)

NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [rgb(255, 255, 255, 0.16), rgb(255, 255, 255, 0)])!
    .draw(fromCenter: NSPoint(x: 512, y: 980), radius: 0, toCenter: NSPoint(x: 512, y: 980), radius: 700, options: [])
let rim = squircle(body.insetBy(dx: 2, dy: 2))
rim.lineWidth = 4
NSGradient(colors: [p.rimLight, p.rimLight.withAlphaComponent(0)], atLocations: [0, 0.5], colorSpace: .sRGB)!
    .draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: -90)
NSGraphicsContext.restoreGraphicsState()

let highlight = squircle(body.insetBy(dx: 2, dy: 2))
highlight.lineWidth = 4
NSGraphicsContext.saveGraphicsState()
let rimImage = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
    NSColor.white.setStroke()
    highlight.stroke()
    NSGraphicsContext.current?.compositingOperation = .sourceIn
    NSGradient(colors: [p.rimLight, p.rimLight.withAlphaComponent(0)], atLocations: [0, 0.6], colorSpace: .sRGB)!
        .draw(in: r, angle: -90)
    return true
}
rimImage.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()

let concept = args.count > 3 ? args[3] : "sparkle"

func sparkle(_ c: NSPoint, _ r: CGFloat, waist: CGFloat = 0.14) -> NSBezierPath {
    let path = NSBezierPath()
    let tips = [NSPoint(x: c.x, y: c.y + r), NSPoint(x: c.x + r, y: c.y),
                NSPoint(x: c.x, y: c.y - r), NSPoint(x: c.x - r, y: c.y)]
    path.move(to: tips[0])
    for i in 0..<4 {
        let a = tips[i], b = tips[(i + 1) % 4]
        let k = r * waist
        let q = NSPoint(x: c.x + ((a.x - c.x) + (b.x - c.x)) / r * k, y: c.y + ((a.y - c.y) + (b.y - c.y)) / r * k)
        path.curve(to: b, controlPoint1: q, controlPoint2: q)
    }
    path.close()
    return path
}

func capsule(_ r: NSRect) -> NSBezierPath {
    let rad = min(r.width, r.height) / 2
    return NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad)
}

let fills = NSBezierPath()
var strokes: [NSBezierPath] = []
var accents: [(NSBezierPath, NSColor)] = []

switch concept {
case "cursor":
    let cx: CGFloat = 470, w: CGFloat = 60
    fills.append(capsule(NSRect(x: cx - w / 2, y: 270, width: w, height: 480)))
    fills.append(capsule(NSRect(x: cx - 120, y: 700, width: 240, height: w)))
    fills.append(capsule(NSRect(x: cx - 120, y: 270, width: 240, height: w)))
    fills.append(sparkle(NSPoint(x: 690, y: 680), 118))
    fills.append(sparkle(NSPoint(x: 735, y: 470), 52))
case "eraser":
    let wave = NSBezierPath()
    wave.lineWidth = 46
    wave.lineCapStyle = .round
    wave.lineJoinStyle = .round
    var x: CGFloat = 236
    let y0: CGFloat = 330, step: CGFloat = 66
    wave.move(to: NSPoint(x: x, y: y0))
    for i in 0..<3 {
        let dy: CGFloat = i % 2 == 0 ? 54 : -54
        wave.curve(to: NSPoint(x: x + step, y: y0), controlPoint1: NSPoint(x: x + step * 0.3, y: y0 + dy),
                   controlPoint2: NSPoint(x: x + step * 0.7, y: y0 + dy))
        x += step
    }
    wave.line(to: NSPoint(x: 790, y: y0))
    strokes.append(wave)
    var t = AffineTransform()
    t.translate(x: 610, y: 590)
    t.rotate(byDegrees: 35)
    let body = NSBezierPath(roundedRect: NSRect(x: -200, y: -95, width: 400, height: 190), xRadius: 54, yRadius: 54)
    body.transform(using: t)
    fills.append(body)
    let sleeve = NSBezierPath(rect: NSRect(x: -40, y: -95, width: 90, height: 190))
    sleeve.transform(using: t)
    accents.append((sleeve, rgb(0, 0, 0, 0.22)))
default:
    fills.append(sparkle(NSPoint(x: 470, y: 470), 270))
    fills.append(sparkle(NSPoint(x: 718, y: 724), 92))
    fills.append(sparkle(NSPoint(x: 752, y: 330), 54))
}

let glyphLayer = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
    NSColor.white.setFill()
    fills.fill()
    NSColor.white.setStroke()
    strokes.forEach { $0.stroke() }
    NSGraphicsContext.current?.compositingOperation = .sourceIn
    NSGradient(starting: p.glyphTop, ending: p.glyphBottom)!
        .draw(in: NSRect(x: 0, y: 200, width: 1024, height: 620), angle: -90)
    NSGraphicsContext.current?.compositingOperation = .sourceAtop
    for (path, color) in accents { color.setFill(); path.fill() }
    return true
}

NSGraphicsContext.saveGraphicsState()
let glyphShadow = NSShadow()
glyphShadow.shadowColor = p.glyphShadow
glyphShadow.shadowBlurRadius = 22
glyphShadow.shadowOffset = NSSize(width: 0, height: -10)
glyphShadow.set()
glyphLayer.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print(out)
