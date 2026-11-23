import SwiftUI

/// A small SVG path-data parser, so the design's hand-drawn marks render exactly as drawn.
enum SVG {
    static func path(_ d: String) -> Path {
        var p = Path()
        let s = Array(d.utf8)
        var i = 0
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCtrl: CGPoint?
        var cmd: UInt8 = 0

        func skip() {
            while i < s.count, s[i] == 32 || s[i] == 44 || s[i] == 10 || s[i] == 9 || s[i] == 13 { i += 1 }
        }
        func num() -> CGFloat {
            skip()
            let st = i
            if i < s.count, s[i] == 43 || s[i] == 45 { i += 1 }
            var dot = false
            while i < s.count {
                let c = s[i]
                if c >= 48 && c <= 57 {
                    i += 1
                } else if c == 46 && !dot {
                    dot = true
                    i += 1
                } else {
                    break
                }
            }
            return CGFloat(Double(String(decoding: s[st..<i], as: UTF8.self)) ?? 0)
        }
        func flag() -> Bool {
            skip()
            let v = i < s.count && s[i] == 49
            i += 1
            return v
        }
        func point(_ rel: Bool) -> CGPoint {
            let x = num(), y = num()
            return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
        }

        while true {
            skip()
            guard i < s.count else { break }
            let c = s[i]
            if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) {
                cmd = c
                i += 1
            } else if cmd == 77 {
                cmd = 76
            } else if cmd == 109 {
                cmd = 108
            } else if cmd == 0 || cmd == 90 || cmd == 122 {
                break
            }
            let rel = cmd >= 97
            var ctrl: CGPoint?
            switch cmd & ~32 {
            case 77:  // M
                cur = point(rel)
                start = cur
                p.move(to: cur)
            case 76:  // L
                cur = point(rel)
                p.addLine(to: cur)
            case 72:  // H
                let x = num()
                cur.x = rel ? cur.x + x : x
                p.addLine(to: cur)
            case 86:  // V
                let y = num()
                cur.y = rel ? cur.y + y : y
                p.addLine(to: cur)
            case 67:  // C
                let c1 = point(rel), c2 = point(rel), e = point(rel)
                p.addCurve(to: e, control1: c1, control2: c2)
                ctrl = c2
                cur = e
            case 83:  // S
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = point(rel), e = point(rel)
                p.addCurve(to: e, control1: c1, control2: c2)
                ctrl = c2
                cur = e
            case 81:  // Q
                let c1 = point(rel), e = point(rel)
                p.addQuadCurve(to: e, control: c1)
                ctrl = c1
                cur = e
            case 84:  // T
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let e = point(rel)
                p.addQuadCurve(to: e, control: c1)
                ctrl = c1
                cur = e
            case 65:  // A
                let rx = num(), ry = num(), rot = num()
                let large = flag(), sweep = flag()
                let e = point(rel)
                arc(&p, from: cur, to: e, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                cur = e
            case 90:  // Z
                p.closeSubpath()
                cur = start
            default:
                return p
            }
            lastCtrl = ctrl
        }
        return p
    }

    private static func arc(
        _ p: inout Path, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
        rotation: CGFloat, large: Bool, sweep: Bool
    ) {
        var rx = abs(rx0), ry = abs(ry0)
        guard rx > 0, ry > 0, p0 != p1 else {
            p.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
        let lam = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lam > 1 {
            rx *= sqrt(lam)
            ry *= sqrt(lam)
        }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den == 0 ? 0 : sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry, cy1 = -coef * ry * x1 / rx
        let cx = cosP * cx1 - sinP * cy1 + (p0.x + p1.x) / 2
        let cy = sinP * cx1 + cosP * cy1 + (p0.y + p1.y) / 2
        let t1 = atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
        var dt = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx) - t1
        if sweep && dt < 0 { dt += 2 * .pi } else if !sweep && dt > 0 { dt -= 2 * .pi }
        let n = max(1, Int(ceil(abs(dt) / (.pi / 2) - 1e-9)))
        let delta = dt / CGFloat(n)
        let k = 4 / 3 * tan(delta / 4)
        func at(_ a: CGFloat) -> CGPoint {
            CGPoint(
                x: cx + rx * cos(a) * cosP - ry * sin(a) * sinP,
                y: cy + rx * cos(a) * sinP + ry * sin(a) * cosP)
        }
        func tangent(_ a: CGFloat) -> CGPoint {
            CGPoint(
                x: -rx * sin(a) * cosP - ry * cos(a) * sinP,
                y: -rx * sin(a) * sinP + ry * cos(a) * cosP)
        }
        for j in 0..<n {
            let a1 = t1 + CGFloat(j) * delta, a2 = a1 + delta
            let e1 = at(a1), e2 = at(a2), d1 = tangent(a1), d2 = tangent(a2)
            p.addCurve(
                to: e2,
                control1: CGPoint(x: e1.x + k * d1.x, y: e1.y + k * d1.y),
                control2: CGPoint(x: e2.x - k * d2.x, y: e2.y - k * d2.y))
        }
    }
}

/// SVG path data scaled from its view box into the shape's rect.
struct SVGShape: Shape {
    let d: String
    var box = CGSize(width: 18, height: 18)

    init(_ d: String, box: CGFloat = 18) {
        self.d = d
        self.box = CGSize(width: box, height: box)
    }

    init(_ d: String, box: CGSize) {
        self.d = d
        self.box = box
    }

    func path(in rect: CGRect) -> Path {
        SVG.path(d).applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: rect.width / box.width, y: rect.height / box.height))
    }
}

private let round125 = StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)

/// The app's mark: a small conifer.
struct TreeLogo: View {
    var size: CGFloat = 18
    var body: some View {
        ZStack {
            SVGShape("M9 2.5 4.5 9h2.25L4 13h10l-2.75-4h2.25Z").fill(T.leafFg.opacity(0.3))
            SVGShape("M9 2.5 4.5 9h2.25L4 13h10l-2.75-4h2.25ZM9 13v2.5")
                .stroke(T.leafFg, style: StrokeStyle(lineWidth: 1.25 * size / 18, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

/// Running: a tree in full leaf.
struct RunningMark: View {
    var body: some View {
        ZStack {
            SVGShape("M5.25 11.75a3 3 0 0 1-.55-5.95 4.4 4.4 0 0 1 8.6 0 3 3 0 0 1-.55 5.95Z")
                .fill(T.leafFg.opacity(0.3))
            SVGShape(
                "M5.25 11.75a3 3 0 0 1-.55-5.95 4.4 4.4 0 0 1 8.6 0 3 3 0 0 1-.55 5.95ZM9 11.75V16M9 13.75l1.6-1.4M5.5 16h7"
            )
            .stroke(T.leafFg, style: round125)
        }
        .frame(width: 18, height: 18)
    }
}

/// Stopped: a bare winter tree, dormant.
struct DormantMark: View {
    var body: some View {
        SVGShape(
            "M9 16V4M9 11.5 5.75 8.25M5.75 8.25 5.25 6M5.75 8.25 3.9 7.6M9 9.75l3-3M12 6.75l.3-2M12 6.75l1.9-.45M9 6.5 7.5 5M5.5 16h7"
        )
        .stroke(T.bark.opacity(0.7), style: round125)
        .frame(width: 18, height: 18)
    }
}

/// Starting: a sapling whose two leaves swell and settle while the stack boots.
struct SaplingMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    private let leaves =
        "M9 12C6.4 12 4.75 10.4 4.75 8.1 7.35 8.1 9 9.7 9 12ZM9 10.25c0-2.35 1.65-3.95 4.25-3.95 0 2.35-1.65 3.95-4.25 3.95Z"

    var body: some View {
        ZStack {
            SVGShape("M9 16V9.5M5.5 16h7").stroke(T.amberFg, style: round125)
            ZStack {
                SVGShape(leaves).fill(T.amberFg.opacity(0.25))
                SVGShape(leaves).stroke(T.amberFg, style: round125)
            }
            .scaleEffect(reduceMotion || grown ? 1 : 0.8, anchor: UnitPoint(x: 0.5, y: 12.0 / 18.0))
        }
        .frame(width: 18, height: 18)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { grown = true }
        }
    }
}

/// Lucide's git glyphs, drawn from their path data on a 24 grid.
struct GitGlyph: View {
    enum Kind: String {
        case branch = "M6 3v12M21 6a3 3 0 1 1-6 0a3 3 0 1 1 6 0M9 18a3 3 0 1 1-6 0a3 3 0 1 1 6 0M18 9a9 9 0 0 1-9 9"
        case pullRequest =
            "M21 18a3 3 0 1 1-6 0a3 3 0 1 1 6 0M9 6a3 3 0 1 1-6 0a3 3 0 1 1 6 0M13 6h3a2 2 0 0 1 2 2v7M6 9v12"
        case draft = "M21 18a3 3 0 1 1-6 0a3 3 0 1 1 6 0M9 6a3 3 0 1 1-6 0a3 3 0 1 1 6 0M18 6V5M18 11v-1M6 9v12"
        case merge = "M21 18a3 3 0 1 1-6 0a3 3 0 1 1 6 0M9 6a3 3 0 1 1-6 0a3 3 0 1 1 6 0M6 21V9a9 9 0 0 0 9 9"
        case commit = "M15 12a3 3 0 1 1-6 0a3 3 0 1 1 6 0M3 12h6M15 12h6"
    }

    let kind: Kind
    var size: CGFloat = 15
    var color: Color = T.fg

    var body: some View {
        SVGShape(kind.rawValue, box: 24)
            .stroke(color, style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// A free slot as a clearing: open ground, grass, a low sun, and the outline of the tree to come.
struct ClearingIllustration: View {
    private let box = CGSize(width: 200, height: 80)
    private let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

    var body: some View {
        ZStack {
            SVGShape("M163 20a7 7 0 1 1-14 0a7 7 0 1 1 14 0", box: box).stroke(T.amber, style: style)
            SVGShape("M86 50a11 11 0 0 1-2-21.8 17 17 0 0 1 32 0A11 11 0 0 1 114 50ZM100 50v20", box: box)
                .stroke(T.subtle, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [3, 4]))
            SVGShape("M84 70q16-6 32 0", box: box).stroke(T.bark, style: style)
            SVGShape("M8 70h184", box: box).stroke(T.subtle, style: style)
            SVGShape("M34 70l-2-6M34 70l1-7M34 70l4-5M158 70l-2-5M158 70l1.5-6M158 70l3.5-4", box: box)
                .stroke(T.leafFg, style: style)
        }
        .frame(width: 200, height: 80)
        .accessibilityLabel("An empty clearing: this slot is free and ready for the next branch")
    }
}

/// A faint stand of giant sequoias behind the tiles. Atmosphere only.
struct SequoiaBackdrop: View {
    private struct Tree {
        let x: Double, h: Double, w: Double, seed: Double
    }

    private let far: [Tree] = [
        .init(x: 70, h: 420, w: 18, seed: 3), .init(x: 300, h: 470, w: 20, seed: 11),
        .init(x: 470, h: 400, w: 16, seed: 19), .init(x: 790, h: 450, w: 19, seed: 27),
        .init(x: 930, h: 410, w: 17, seed: 35), .init(x: 1150, h: 460, w: 20, seed: 43),
    ]
    private let near: [Tree] = [
        .init(x: 170, h: 600, w: 40, seed: 5), .init(x: 660, h: 625, w: 48, seed: 17),
        .init(x: 1050, h: 580, w: 42, seed: 29),
    ]

    var body: some View {
        Canvas { ctx, size in
            // preserveAspectRatio="xMidYMax slice" on a 1200 x 640 view box.
            let scale = max(size.width / 1200, size.height / 640)
            ctx.translateBy(x: (size.width - 1200 * scale) / 2, y: size.height - 640 * scale)
            ctx.scaleBy(x: scale, y: scale)
            ctx.drawLayer { layer in
                layer.opacity = 0.55
                for t in far { draw(t, in: &layer, trunk: 0.09, crown: 0.07) }
            }
            for t in near { draw(t, in: &ctx, trunk: 0.16, crown: 0.11) }
            ctx.fill(SVG.path("M0 628 Q300 618 600 626 T1200 622 V640 H0Z"), with: .color(T.bark.opacity(0.08)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rand(_ n: Double) -> Double {
        let s = sin(n * 12.9898) * 43758.5453
        return s - floor(s)
    }

    private func draw(_ t: Tree, in ctx: inout GraphicsContext, trunk: Double, crown: Double) {
        let ground = 640.0, top = ground - t.h
        let crownDepth = t.h * 0.5, neck = top + t.h * 0.12
        let x = t.x, w = t.w
        var p = Path()
        p.move(to: CGPoint(x: x - w * 0.85, y: ground))
        p.addQuadCurve(to: CGPoint(x: x - w * 0.5, y: ground - 40), control: CGPoint(x: x - w * 0.5, y: ground - 14))
        p.addLine(to: CGPoint(x: x - w * 0.14, y: neck))
        p.addLine(to: CGPoint(x: x, y: top))
        p.addLine(to: CGPoint(x: x + w * 0.14, y: neck))
        p.addLine(to: CGPoint(x: x + w * 0.5, y: ground - 40))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.85, y: ground), control: CGPoint(x: x + w * 0.5, y: ground - 14))
        p.closeSubpath()
        ctx.fill(p, with: .color(T.bark.opacity(trunk)))

        let levels = 9
        let fill = GraphicsContext.Shading.color(T.matrix.opacity(crown))
        for i in 0..<levels {
            let f = Double(i) / Double(levels - 1)
            let cy = top + 10 + f * crownDepth
            let spread = w * (0.5 + f * 1.6)
            let side: Double = i % 2 == 0 ? -1 : 1
            let jitter = rand(t.seed + Double(i)) * w * 0.5
            let rx = w * (0.55 + f * 0.75) + rand(t.seed + Double(i) * 3) * w * 0.3
            ellipse(&ctx, cx: x + side * (spread * 0.55 + jitter), cy: cy, rx: rx, with: fill)
            if i > 1 {
                ellipse(&ctx, cx: x - side * (spread * 0.4 + jitter * 0.5), cy: cy + 8, rx: rx * 0.8, with: fill)
            }
        }
    }

    private func ellipse(
        _ ctx: inout GraphicsContext, cx: Double, cy: Double, rx: Double, with fill: GraphicsContext.Shading
    ) {
        let ry = rx * 0.42
        ctx.fill(Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)), with: fill)
    }
}
