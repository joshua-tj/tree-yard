import AppKit
import CoreText
import SwiftUI

/// An OKLCH colour, converted to sRGB. The design's tokens are written in OKLCH.
func oklch(_ l: Double, _ c: Double, _ h: Double, _ alpha: Double = 1) -> Color {
    let hr = h * .pi / 180
    let a = c * cos(hr), b = c * sin(hr)
    let l_ = l + 0.3963377774 * a + 0.2158037573 * b
    let m_ = l - 0.1055613458 * a - 0.0638541728 * b
    let s_ = l - 0.0894841775 * a - 1.2914855480 * b
    let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
    func gamma(_ x: Double) -> Double {
        let v = min(max(x, 0), 1)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
    return Color(
        .sRGB,
        red: gamma(4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S),
        green: gamma(-1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S),
        blue: gamma(-0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S),
        opacity: alpha
    )
}

/// Grove: parchment ground, forest-green ink, leaf for running, amber for starting, berry for stop.
enum T {
    static let canvas = oklch(0.974, 0.014, 92)
    static let raised = oklch(0.992, 0.007, 92)
    static let chrome = oklch(0.946, 0.02, 92)
    static let fg = oklch(0.27, 0.045, 152)
    static let muted = oklch(0.27, 0.045, 152, 0.64)
    static let subtle = oklch(0.27, 0.045, 152, 0.42)
    static let surface = oklch(0.27, 0.045, 152, 0.04)
    static let line = oklch(0.35, 0.05, 120, 0.16)
    static let lineHover = oklch(0.35, 0.05, 120, 0.32)
    static let ring = oklch(0.36, 0.07, 152, 0.45)

    static let matrix = oklch(0.36, 0.07, 152)
    static let matrixHover = oklch(0.41, 0.075, 152)
    static let matrixActive = oklch(0.33, 0.07, 152)
    static let onMatrix = oklch(0.98, 0.012, 92)
    static let matrixMuted = oklch(0.36, 0.07, 152, 0.06)
    static let matrixMutedHover = oklch(0.36, 0.07, 152, 0.10)
    static let matrixMutedActive = oklch(0.36, 0.07, 152, 0.14)
    static let matrixBorder = oklch(0.35, 0.05, 120, 0.2)
    static let matrixBorderHover = oklch(0.35, 0.05, 120, 0.36)

    static let leaf = oklch(0.72, 0.14, 138)
    static let leafFg = oklch(0.46, 0.12, 140)

    static let amber = oklch(0.74, 0.13, 68)
    static let amberFg = oklch(0.52, 0.12, 58)
    static let amberMuted = oklch(0.74, 0.13, 68, 0.14)
    static let amberBorder = oklch(0.70, 0.13, 68, 0.5)

    static let ruby = oklch(0.52, 0.15, 22)
    static let rubyHover = oklch(0.48, 0.15, 22)
    static let rubyActive = oklch(0.45, 0.15, 22)
    static let rubyFg = oklch(0.48, 0.15, 22)
    static let rubyMuted = oklch(0.52, 0.15, 22, 0.12)
    static let rubyMutedHover = oklch(0.52, 0.15, 22, 0.18)
    static let rubyMutedActive = oklch(0.52, 0.15, 22, 0.24)
    static let rubyBorder = oklch(0.52, 0.15, 22, 0.45)

    static let skyFg = oklch(0.52, 0.13, 240.6)
    static let pulseFg = oklch(0.52, 0.087, 298.9)
    static let bark = oklch(0.45, 0.05, 55)

    /// color-mix(in oklch, raised, leaf 28%) and (raised, amber 16%).
    static let tileRunning = oklch(0.9158, 0.0442, 104.9)
    static let tileStarting = oklch(0.9517, 0.0267, 88.2)
    static let tileRunningBorder = oklch(0.46, 0.12, 140, 0.45)

    static let scrim = Color.black.opacity(0.4)
}

enum Fonts {
    private static var hasFraunces = false

    static func register() {
        if let url = Bundle.main.url(forResource: "Fraunces", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        hasFraunces = NSFontManager.shared.availableMembers(ofFontFamily: "Fraunces") != nil
    }

    /// Fraunces, the design's display face; the system serif when it is missing.
    static func display(_ size: CGFloat, weight: CGFloat = 500) -> Font {
        guard hasFraunces else {
            return .system(size: size, weight: weight >= 600 ? .semibold : .medium, design: .serif)
        }
        let wght = 0x7767_6874, opsz = 0x6F70_737A
        let attrs: [CFString: Any] = [
            kCTFontFamilyNameAttribute: "Fraunces",
            kCTFontVariationAttribute: [wght: weight, opsz: min(max(size, 9), 144)],
        ]
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(desc, size, nil))
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// The design system's button: solid, soft, outline or ghost, in forest green or berry.
struct AuroraButtonStyle: ButtonStyle {
    enum Variant { case solid, soft, outline, ghost }
    enum Tone { case matrix, ruby }

    var variant: Variant = .solid
    var tone: Tone = .matrix
    var size: Int = 1
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        Chrome(style: self, configuration: configuration)
    }

    private struct Chrome: View {
        let style: AuroraButtonStyle
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            let h: CGFloat = style.size == 1 ? 28 : 36
            let pressed = configuration.isPressed
            let active = enabled && hover
            configuration.label
                .font(.system(size: style.size == 1 ? 12 : 14, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(foreground)
                .padding(.horizontal, style.iconOnly ? 0 : (style.size == 1 ? 12 : 16))
                .frame(width: style.iconOnly ? h : nil, height: h)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(background(hover: active, pressed: pressed))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(border(hover: active), lineWidth: style.variant == .outline ? 1 : 0)
                )
                .shadow(
                    color: style.variant == .solid || style.variant == .soft ? Color.black.opacity(0.12) : .clear,
                    radius: 0.75, y: 0.75
                )
                .opacity(enabled ? (style.variant == .ghost && !active ? 0.7 : 1) : 0.5)
                .pointerCursor(enabled)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.1), value: hover)
        }

        private var foreground: Color {
            switch (style.variant, style.tone) {
            case (.solid, .matrix): return T.onMatrix
            case (.solid, .ruby): return .white
            case (_, .matrix): return T.fg
            case (_, .ruby): return T.rubyFg
            }
        }

        private func background(hover: Bool, pressed: Bool) -> Color {
            let ruby = style.tone == .ruby
            switch style.variant {
            case .solid:
                if pressed { return ruby ? T.rubyActive : T.matrixActive }
                if hover { return ruby ? T.rubyHover : T.matrixHover }
                return ruby ? T.ruby : T.matrix
            case .soft:
                if pressed { return ruby ? T.rubyMutedActive : T.matrixMutedActive }
                if hover { return ruby ? T.rubyMutedHover : T.matrixMutedHover }
                return ruby ? T.rubyMuted : T.matrixMuted
            case .outline:
                if pressed { return T.canvas }
                return hover ? oklch(0.955, 0.012, 100) : T.raised
            case .ghost:
                if pressed { return T.matrixMutedActive }
                return hover ? T.matrixMuted : .clear
            }
        }

        private func border(hover: Bool) -> Color {
            guard style.variant == .outline else { return .clear }
            if style.tone == .ruby { return T.rubyBorder }
            return hover ? T.matrixBorderHover : T.matrixBorder
        }
    }
}

extension ButtonStyle where Self == AuroraButtonStyle {
    static func aurora(
        _ variant: AuroraButtonStyle.Variant, tone: AuroraButtonStyle.Tone = .matrix, size: Int = 1,
        iconOnly: Bool = false
    ) -> AuroraButtonStyle {
        AuroraButtonStyle(variant: variant, tone: tone, size: size, iconOnly: iconOnly)
    }
}

/// The raised card surface shared by the tiles and the main-branch strip.
struct CardBackground: View {
    var fill: Color = T.raised
    var border: Color = T.line
    var radius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .shadow(color: oklch(0.4, 0.05, 90, 0.08), radius: 1, y: 1)
            .shadow(color: oklch(0.4, 0.05, 90, 0.10), radius: 5, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border, lineWidth: 1)
            )
    }
}

/// One row of a dropdown menu.
struct MenuItem: Identifiable {
    enum Icon {
        case symbol(String)
        case branch
        /// A status dot, for a row that reports on something.
        case dot(Color)
    }

    let id = UUID()
    var title = ""
    var icon: Icon?
    /// Quiet monospaced text at the row's right edge, such as a port.
    var detail: String?
    var destructive = false
    var checked = false
    var separator = false
    var action: () -> Void = {}

    static var divider: MenuItem { MenuItem(separator: true) }
}

/// A dropdown to show: its rows and the button it hangs from, in window coordinates.
struct MenuRequest: Identifiable {
    let id = UUID()
    var items: [MenuItem]
    var anchor: CGRect
    /// Line the menu's right edge up with the button's, as the tile's "more" menu does.
    var alignTrailing = false
    /// Hang from the top of the content, for a button that sits in the title bar.
    var belowTitleBar = false
}

/// The design system's dropdown: a raised card of rows, drawn over the window's content.
struct MenuLayer: View {
    let request: MenuRequest
    let dismiss: () -> Void

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let height = estimatedHeight
            let below = request.anchor.maxY - origin.y + 4
            let above = request.anchor.minY - origin.y - 4 - height
            let y = request.belowTitleBar ? 6 : (below + height > geo.size.height - 8 && above > 8 ? above : below)
            let x = (request.alignTrailing ? request.anchor.maxX : request.anchor.minX) - origin.x
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: dismiss)
                card
                    .fixedSize()
                    .alignmentGuide(.leading) { d in request.alignTrailing ? d.width : 0 }
                    .offset(x: max(x, request.alignTrailing ? 0 : 8), y: y)
            }
        }
        .background(
            Button("", action: dismiss).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)
        )
    }

    private var estimatedHeight: CGFloat {
        request.items.reduce(10) { $0 + ($1.separator ? 9 : 28) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(request.items) { item in
                if item.separator {
                    Rectangle().fill(T.line).frame(height: 1).padding(.vertical, 4).padding(.horizontal, -4)
                } else {
                    MenuRow(item: item, dismiss: dismiss)
                }
            }
        }
        .padding(4)
        .frame(minWidth: 176)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(T.raised)
                .shadow(color: oklch(0.4, 0.05, 90, 0.10), radius: 2, y: 1)
                .shadow(color: oklch(0.4, 0.05, 90, 0.18), radius: 14, y: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(T.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .clear, radius: 0)
    }
}

private struct MenuRow: View {
    let item: MenuItem
    let dismiss: () -> Void
    @State private var hover = false

    var body: some View {
        let color = item.destructive ? T.rubyFg : T.fg
        Button {
            dismiss()
            item.action()
        } label: {
            HStack(spacing: 8) {
                switch item.icon {
                case .symbol(let name):
                    Image(systemName: name).font(.system(size: 11, weight: .medium)).frame(width: 15, height: 15)
                case .branch:
                    GitGlyph(kind: .branch, size: 14, color: color)
                case .dot(let tone):
                    Circle().fill(tone).frame(width: 7, height: 7).frame(width: 15, height: 15)
                case nil:
                    EmptyView()
                }
                Text(item.title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 340, alignment: .leading)
                Spacer(minLength: 16)
                if let detail = item.detail {
                    Text(verbatim: detail).font(Fonts.mono(11)).foregroundStyle(T.muted)
                }
                if item.checked {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(T.muted)
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hover ? (item.destructive ? T.rubyMuted : T.matrixMutedHover) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hover = $0 }
    }
}

/// Reports a view's frame in window coordinates, so a menu can hang from it.
struct FrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

extension View {
    func trackFrame(_ frame: Binding<CGRect>) -> some View {
        background(GeometryReader { geo in Color.clear.preference(key: FrameKey.self, value: geo.frame(in: .global)) })
            .onPreferenceChange(FrameKey.self) { frame.wrappedValue = $0 }
    }
}

/// "40 min ago", "3 h ago", "yesterday", "4 days ago".
func ago(_ date: Date, now: Date = Date()) -> String {
    let s = max(0, now.timeIntervalSince(date))
    if s < 60 { return "just now" }
    if s < 3600 { return "\(Int(s / 60)) min ago" }
    if s < 86400 { return "\(Int(s / 3600)) h ago" }
    let days = Int(s / 86400)
    if days == 1 { return "yesterday" }
    if days < 60 { return "\(days) days ago" }
    if days < 730 { return "\(days / 30) months ago" }
    return "\(days / 365) years ago"
}

extension View {
    /// The pointing-hand cursor that the design uses over anything clickable.
    @ViewBuilder func pointerCursor(_ on: Bool = true) -> some View {
        if #available(macOS 15, *), on {
            pointerStyle(.link)
        } else {
            self
        }
    }
}

/// The design's tooltip: a small dark label above a control, shown after a short hover.
/// Used for icon-only buttons, where it stands in for the missing label.
private struct Tip: ViewModifier {
    let text: String
    @State private var shown = Tip.forced
    @State private var pending: Task<Void, Never>?

    private static let height: CGFloat = 22
    #if DEBUG
    /// `TREEYARD_TIPS=1` shows every tooltip at once, for checking their placement in a snapshot.
    private static let forced = ProcessInfo.processInfo.environment["TREEYARD_TIPS"] != nil
    #else
    private static let forced = false
    #endif

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                pending?.cancel()
                if inside {
                    pending = Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        if !Task.isCancelled { shown = true }
                    }
                } else {
                    shown = false
                }
            }
            .simultaneousGesture(TapGesture().onEnded {
                pending?.cancel()
                shown = false
            })
            .overlay(alignment: .top) {
                if shown {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(T.raised)
                        .padding(.horizontal, 7)
                        .frame(height: Self.height)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(oklch(0.27, 0.045, 152)))
                        .fixedSize()
                        // Sits wholly above the control, with a gap, so it never covers what is hovered.
                        .offset(y: -(Self.height + 6))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: shown)
            .zIndex(shown ? 10 : 0)
    }
}

extension View {
    func tip(_ text: String) -> some View { modifier(Tip(text: text)) }
}
