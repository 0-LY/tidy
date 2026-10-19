import json, math, os, sys

out = sys.argv[1]
concept = sys.argv[2] if len(sys.argv) > 2 else "pebbles"
theme = sys.argv[3] if len(sys.argv) > 3 else "khaki"
os.makedirs(f"{out}/Assets", exist_ok=True)
for f in os.listdir(f"{out}/Assets"):
    os.remove(f"{out}/Assets/{f}")

def p3(hexstr):
    h = hexstr.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"display-p3:{r:.4f},{g:.4f},{b:.4f},1.0"


THEMES = {
    "olive": {"bg": [p3("#55603F"), p3("#2B3221")], "ink": p3("#E9EAE4"), "ink2": p3("#C9CCC2")},
    "sage": {"bg": [p3("#9AA67E"), p3("#66724F")], "ink": p3("#F7F5EE"), "ink2": p3("#E6E3D8")},
    "stone": {"bg": [p3("#D9D8D2"), p3("#A9A8A0")], "ink": p3("#4A5434"), "ink2": p3("#6B7550")},
    "graphite": {"bg": [p3("#4B4E52"), p3("#1C1E20")], "ink": p3("#CDD1A6"), "ink2": p3("#959B6C")},
    "sand": {"bg": [p3("#D2CDB0"), p3("#A6A07E")], "ink": p3("#3E4A2C"), "ink2": p3("#566240")},
    "khaki": {"bg": ["display-p3:0.44,0.46,0.31,1.0", "display-p3:0.21,0.24,0.14,1.0"],
              "ink": "display-p3:0.93,0.93,0.91,1.0", "ink2": "display-p3:0.70,0.71,0.68,1.0"},
    "dark": {"bg": ["display-p3:0.50,0.51,0.54,1.0", "display-p3:0.17,0.18,0.20,1.0"],
             "ink": "display-p3:1.0,1.0,1.0,1.0", "ink2": "display-p3:0.78,0.79,0.82,1.0"},
}
t = THEMES[theme]


def sparkle(cx, cy, r, waist=0.14):
    k = r * waist
    pts = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    ctl = [(cx + k, cy - k), (cx + k, cy + k), (cx - k, cy + k), (cx - k, cy - k)]
    d = f"M{pts[0][0]},{pts[0][1]}"
    for i in range(4):
        n = pts[(i + 1) % 4]
        d += f" Q{ctl[i][0]},{ctl[i][1]} {n[0]},{n[1]}"
    return d + " Z"


def capsule(x, y, w, h, extra=""):
    r = min(w, h) / 2
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{r:.1f}" ry="{r:.1f}" {extra}/>'


def svg(name, body):
    with open(f"{out}/Assets/{name}", "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
                f'<g fill="#FFFFFF">{body}</g></svg>')


def stroke(d, w):
    return (f'<path d="{d}" fill="none" stroke="#FFFFFF" stroke-width="{w}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


def poly(points):
    return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in points) + " Z"


def band(fn, x0, x1, half, steps=160):
    top, bot = [], []
    for i in range(steps + 1):
        x = x0 + (x1 - x0) * i / steps
        y = fn(x)
        dx = 1e-3
        dy = (fn(x + dx) - fn(x - dx)) / (2 * dx)
        n = math.hypot(1, dy)
        nx, ny = -dy / n, 1 / n
        top.append((x + nx * half, y + ny * half))
        bot.append((x - nx * half, y - ny * half))
    cap = []
    for side, (px, py), ang0 in ((1, (x1, fn(x1)), -90), (0, (x0, fn(x0)), 90)):
        pass
    return poly(top + bot[::-1])


groups = []
if concept == "nib":
    body = ("M318,312 C318,262 360,236 410,236 L614,236 C664,236 706,262 706,312 "
            "C706,450 614,620 512,812 C410,620 318,450 318,312 Z")
    hole = "M512,396 m-40,0 a40,40 0 1,0 80,0 a40,40 0 1,0 -80,0 Z"
    slit = "M503,430 L521,430 L521,800 L503,800 Z"
    svg("nib.svg", f'<g transform="translate(512 512) scale(1.1) translate(-512 -524)"><path fill-rule="evenodd" d="{body} {hole} {slit}"/></g>')
    groups = [[("nib.svg", "ink")]]
elif concept == "feather":
    right = ("M0,-436 C130,-350 194,-160 184,4 C174,150 106,254 22,300 L9,300 "
             "C8,100 5,-200 1,-374 Z")
    left = ("M-1,-374 C-5,-200 -8,100 -9,300 L-22,300 C-78,278 -116,238 -136,192 "
            "L-98,176 C-152,130 -172,46 -170,-56 C-168,-210 -96,-322 -1,-374 Z")
    quill = "M-10,300 L10,300 C9,362 6,412 2,442 C0,449 -2,449 -3,442 C-6,412 -9,362 -10,300 Z"
    place = '<g transform="translate(548 534) rotate(40) scale(0.86)">'
    svg("right.svg", f'{place}<path d="{right}"/></g>')
    svg("left.svg", f'{place}<path d="{left}"/><path d="{quill}"/></g>')
    svg("spark.svg", f'<path d="{sparkle(292, 300, 104, 0.13)}"/><path d="{sparkle(412, 214, 46, 0.13)}"/>')
    groups = [[("spark.svg", "ink")], [("right.svg", "ink")], [("left.svg", "ink2")]]
elif concept == "strands":
    wave = band(lambda x: 512 + 130 * math.sin((x - 236) / 552 * 2 * math.pi), 236, 788, 46)
    straight = '<rect x="216" y="466" width="592" height="92" rx="46" ry="46"/>'
    ends = ''.join(f'<circle cx="{x}" cy="{512 + 130 * math.sin((x - 236) / 552 * 2 * math.pi):.1f}" r="46"/>' for x in (236, 788))
    svg("wave.svg", f'<path d="{wave}"/>{ends}')
    svg("line.svg", straight)
    groups = [[("line.svg", "ink")], [("wave.svg", "ink2")]]
elif concept == "rays":
    rays = ""
    for i in range(12):
        a = i * 30
        rays += f'<g transform="rotate({a} 512 512)"><rect x="482" y="196" width="60" height="196" rx="30" ry="30"/></g>'
    svg("rays.svg", rays)
    svg("dot.svg", '<circle cx="512" cy="512" r="70"/>')
    groups = [[("dot.svg", "ink2")], [("rays.svg", "ink")]]
elif concept == "ring":
    ring = ("M512,512 m-290,0 a290,290 0 1,0 580,0 a290,290 0 1,0 -580,0 Z "
            "M560,512 m-170,0 a170,170 0 1,1 340,0 a170,170 0 1,1 -340,0 Z")
    svg("ring.svg", f'<path fill-rule="evenodd" d="{ring}"/>')
    groups = [[("ring.svg", "ink")]]
elif concept == "comb":
    teeth = "".join(capsule(250 + i * 85, 450, 50, 300) for i in range(7))
    body = f'<g transform="rotate(-14 512 512)">{capsule(214, 300, 596, 170)}{teeth}</g>'
    svg("comb.svg", body)
    groups = [[("comb.svg", "ink")]]
elif concept == "pebbles":
    svg("p1.svg", '<ellipse cx="512" cy="716" rx="272" ry="112"/>')
    svg("p2.svg", '<ellipse cx="498" cy="534" rx="200" ry="94"/>')
    svg("p3.svg", '<ellipse cx="522" cy="378" rx="130" ry="74"/>')
    groups = [[("p3.svg", "ink")], [("p2.svg", "ink2")], [("p1.svg", "ink")]]
elif concept == "stack":
    svg("s1.svg", f'<g transform="rotate(-11 512 330)">{capsule(262, 280, 500, 104)}</g>')
    svg("s2.svg", f'<g transform="rotate(5 512 500)">{capsule(262, 448, 500, 104)}</g>')
    svg("s3.svg", capsule(262, 640, 500, 104))
    groups = [[("s1.svg", "ink2")], [("s2.svg", "ink2")], [("s3.svg", "ink")]]
elif concept == "untangle":
    d = "M220,650 C320,650 560,610 560,470 C560,360 400,350 380,450 C360,550 480,610 600,610 L804,610"
    svg("line.svg", stroke(d, 70))
    groups = [[("line.svg", "ink")]]
elif concept == "dots":
    pts = [(300, 420, 58), (430, 640, 50), (560, 470, 54)]
    loose = "".join(f'<circle cx="{x}" cy="{y}" r="{r}"/>' for x, y, r in pts)
    neat = "".join(f'<circle cx="{x}" cy="560" r="56"/>' for x in (300, 440, 580, 720))
    svg("loose.svg", loose)
    svg("neat.svg", neat)
    groups = [[("neat.svg", "ink")]]
    svg("neat.svg", "".join(f'<circle cx="{x}" cy="{y}" r="56"/>' for x, y in
                            [(300, 380), (512, 380), (724, 380), (300, 600), (512, 600), (724, 600)]))
    svg("odd.svg", '<circle cx="560" cy="790" r="56"/>')
    svg("slot.svg", '<circle cx="512" cy="820" r="0"/>')
    groups = [[("odd.svg", "ink2")], [("neat.svg", "ink")]]

doc = {
    "fill": {"linear-gradient": t["bg"]},
    "groups": [
        {
            "layers": [{"image-name": n, "name": n[:-4], "glass": True, "fill": {"solid": t[c]}} for n, c in layers],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": 0.25},
            "specular": True,
        }
        for layers in groups
    ],
    "supported-platforms": {"squares": ["macOS"]},
}
with open(f"{out}/icon.json", "w") as f:
    json.dump(doc, f, indent=2)
print(out)
