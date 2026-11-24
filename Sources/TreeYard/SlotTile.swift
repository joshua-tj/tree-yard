import SwiftUI

struct SlotTile: View {
    let slot: Slot
    @EnvironmentObject private var store: Store

    private let height: CGFloat = 268
    @State private var moreFrame = CGRect.zero

    var body: some View {
        if slot.branch == nil && slot.stack == .stopped {
            free
        } else {
            occupied
        }
    }

    private func number(_ color: Color) -> some View {
        Text(slot.id)
            .font(Fonts.display(slot.id.count > 3 ? 28 : 48, weight: 500))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(color)
            .frame(height: 48, alignment: .top)
    }

    // MARK: Free

    private var free: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                number(T.subtle)
                Spacer()
                Text(slot.dirty > 0 ? "Free · \(slot.dirty) uncommitted" : "Free")
                    .font(.system(size: 14))
                    .foregroundStyle(T.muted)
            }
            ClearingIllustration()
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Button {
                    store.dialog = .changeBranch(slot.id)
                } label: {
                    HStack(spacing: 6) {
                        GitGlyph(kind: .branch, size: 12)
                        Text("Checkout")
                    }
                }
                .buttonStyle(.aurora(.soft))

                Button {
                    store.dialog = .newBranch(slot.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        Text("New")
                    }
                }
                .buttonStyle(.aurora(.solid))
            }
        }
        .padding(20)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(T.canvas)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(T.lineHover, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        )
        .opacity(0.9)
        .contextMenu { Button("Show in Finder") { store.revealInFinder(slot.id) } }
    }

    // MARK: Occupied

    private var occupied: some View {
        let stack = slot.stack
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                number(stack == .running ? T.leafFg : T.fg)
                Spacer()
                StackStatus(slot: slot)
            }
            BranchName(branch: slot.branch)
                .padding(.top, 20)
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(T.amberFg)
                .lineLimit(1)
                .frame(height: 16)
                .padding(.top, 2)

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("vs \(store.baseName)").font(.system(size: 12)).foregroundStyle(T.muted)
                    SyncCounts(slot: slot).frame(height: 20)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pull request").font(.system(size: 12)).foregroundStyle(T.muted)
                    PRSummary(slot: slot).frame(height: 20)
                }
            }
            .padding(.top, 12)

            Spacer(minLength: 16)
            Rectangle().fill(T.line).frame(height: 1)
            actions.padding(.top, 16)
        }
        .padding(20)
        .frame(height: height)
        .background(
            CardBackground(
                fill: stack == .running ? T.tileRunning : stack == .starting ? T.tileStarting : T.raised,
                border: stack == .running ? T.tileRunningBorder : stack == .starting ? T.amberBorder : T.line)
        )
        .animation(.easeOut(duration: 0.2), value: stack)
        .contextMenu { Button("Show in Finder") { store.revealInFinder(slot.id) } }
    }

    private var note: String {
        var parts: [String] = []
        if slot.dirty > 0 { parts.append("\(slot.dirty) uncommitted change\(slot.dirty == 1 ? "" : "s")") }
        if let holder = slot.leaseHolder { parts.append("leased by \(holder)") }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        let stack = slot.stack
        let stopped = stack == .stopped
        return HStack(spacing: 8) {
            Button {
                store.toggleStack(slot.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: stopped ? "play.fill" : "stop.fill").font(.system(size: 9))
                    Text(stopped ? "Run" : "Stop")
                }
            }
            .buttonStyle(.aurora(stopped ? .solid : .soft, tone: stopped ? .matrix : .ruby))
            .disabled(stack == .stopping)

            Button {
                store.rebase(slot.id)
            } label: {
                HStack(spacing: 6) {
                    if slot.rebasing {
                        ProgressView().controlSize(.mini).scaleEffect(0.8).frame(width: 11, height: 11)
                    } else {
                        Image(systemName: "arrow.down").font(.system(size: 10, weight: .semibold))
                    }
                    Text("Rebase")
                }
            }
            .buttonStyle(.aurora(.outline))
            .disabled(slot.behind == 0 || slot.rebasing || slot.branch == nil)

            OpenInButton(tip: "Open in VS Code", label: "Open slot \(slot.id) in VS Code") {
                store.openEditor(slot.id)
            } glyph: { hovered in
                AppGlyph(color: hovered ? Color(red: 0.0, green: 0.47, blue: 0.83) : Color(red: 0.28, green: 0.515, blue: 0.695)) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 7.5, weight: .bold))
                }
            }

            OpenInButton(tip: "Open in terminal", label: "Open slot \(slot.id) in a terminal") {
                store.openTerminal(slot.id)
            } glyph: { hovered in
                AppGlyph(color: hovered ? .black : Color(white: 0.3)) {
                    Text(">_").font(.system(size: 8, weight: .bold, design: .monospaced)).fixedSize()
                }
            }

            OpenInButton(tip: "Open in Claude Code", label: "Open slot \(slot.id) in Claude Code") {
                store.openClaude(slot.id)
            } glyph: { hovered in
                if let icon = hovered ? Store.claudeIcon : Store.claudeIconMuted {
                    // App icons carry their own margin, so the artwork matches the 15pt tiles beside it.
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 18, height: 18)
                        .frame(width: 15, height: 15)
                } else {
                    Image(systemName: "sparkle").font(.system(size: 11, weight: .semibold))
                }
            }

            Spacer(minLength: 0)

            Button {
                store.dialog = .release(slot.id)
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.aurora(.ghost, tone: .ruby, iconOnly: true))
            .tip("Release slot")
            .accessibilityLabel("Release slot \(slot.id)")

            Button(action: showMore) {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.aurora(.ghost, iconOnly: true))
            .trackFrame($moreFrame)
            .tip("More")
            .accessibilityLabel("More actions for slot \(slot.id)")
        }
    }

    private func showMore() {
        store.menu = MenuRequest(
            items: [
                MenuItem(title: "Change branch…", icon: .branch, action: { store.dialog = .changeBranch(slot.id) }),
                MenuItem(title: "Show in Finder", icon: .symbol("folder"), action: { store.revealInFinder(slot.id) }),
                MenuItem(title: "Show start log", icon: .symbol("doc.text"), action: { store.openLog(slot.id) }),
            ],
            anchor: moreFrame, alignTrailing: true)
    }
}

/// The branch name, with a copy button that appears while the name is hovered.
private struct BranchName: View {
    let branch: String?
    @EnvironmentObject private var store: Store
    @State private var hover = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 4) {
            // Drop the owner prefix ("joshua/"): everything up to and including the first slash.
            Text(branch.map { $0.split(separator: "/", maxSplits: 1).last.map(String.init) ?? $0 } ?? "detached HEAD")
                .font(Fonts.mono(14, .medium))
                .foregroundStyle(branch == nil ? T.muted : T.fg)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(branch ?? "")
            if let branch {
                Button {
                    store.copy(branch)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copied ? T.leafFg : T.muted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .opacity(hover || copied ? 1 : 0)
                .accessibilityLabel(copied ? "Copied branch name" : "Copy branch name")
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

struct StackStatus: View {
    let slot: Slot
    @EnvironmentObject private var store: Store
    @State private var hover = false
    @State private var servicesFrame = CGRect.zero

    /// "7/8": how many services are up. Quiet while all are; amber once a running stack is missing one.
    @ViewBuilder private var servicesButton: some View {
        if !slot.services.isEmpty {
            let up = slot.services.filter(\.up).count
            let degraded = slot.stack == .running && up < slot.services.count
            Button(action: showServices) {
                HStack(spacing: 3) {
                    Text(verbatim: "\(up)/\(slot.services.count)").font(Fonts.mono(12, .medium)).monospacedDigit()
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(degraded ? T.amberFg : T.muted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .trackFrame($servicesFrame)
            .help("\(up) of \(slot.services.count) services up")
            .accessibilityLabel("\(up) of \(slot.services.count) services up. Show services")
        }
    }

    private func showServices() {
        let id = slot.id
        var items = slot.services.map { service in
            MenuItem(
                title: service.name, icon: .dot(service.up ? T.leafFg : T.subtle), detail: ":\(service.port)",
                action: {
                    if let url = URL(string: "http://localhost:\(service.port)") { NSWorkspace.shared.open(url) }
                })
        }
        items.append(.divider)
        items.append(MenuItem(title: "Show start log", icon: .symbol("doc.text"), action: { store.openLog(id) }))
        store.menu = MenuRequest(items: items, anchor: servicesFrame, alignTrailing: true)
    }

    var body: some View {
        switch slot.stack {
        case .starting:
            VStack(alignment: .trailing, spacing: 6) {
                label("Starting…", color: T.muted) { SaplingMark() }
                servicesButton
            }
        case .stopping:
            label("Stopping…", color: T.muted) { DormantMark() }
        case .stopped:
            label("Stopped", color: T.muted) { DormantMark() }
        case .running:
            VStack(alignment: .trailing, spacing: 6) {
                label("Running", color: T.fg) { RunningMark() }
                HStack(spacing: 10) {
                    servicesButton
                    if let port = slot.port {
                        Button {
                            store.openStack(slot.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text(verbatim: ":\(port)")
                                    .font(Fonts.mono(12, .medium))
                                    .underline(true, color: T.leafFg.opacity(hover ? 1 : 0.4))
                                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(T.leafFg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                        .onHover { hover = $0 }
                        .help("Open the dev stack at localhost:\(port)")
                    }
                }
            }
        }
    }

    private func label(_ text: String, color: Color, @ViewBuilder mark: () -> some View) -> some View {
        HStack(spacing: 8) {
            mark()
            Text(text).font(.system(size: 14)).foregroundStyle(color).fixedSize()
        }
    }
}

struct SyncCounts: View {
    let slot: Slot

    var body: some View {
        if slot.rebasing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).scaleEffect(0.8).frame(width: 13, height: 13)
                Text("Rebasing…").font(.system(size: 14)).foregroundStyle(T.muted)
            }
        } else if slot.branch == nil {
            Text("—").font(.system(size: 14)).foregroundStyle(T.subtle)
        } else if slot.ahead == 0 && slot.behind == 0 && slot.unpushed == 0 {
            Text("Up to date").font(.system(size: 14)).foregroundStyle(T.muted).fixedSize()
        } else {
            // The same three counts, glyphs and colours as the shell prompt; each shows only when above zero.
            HStack(spacing: 10) {
                if slot.behind > 0 {
                    count("↳", slot.behind, T.rubyFg, bold: slot.behind >= staleAfter)
                        .help("\(slot.behind) on main that this branch doesn't have")
                }
                if slot.ahead > 0 {
                    count("↰", slot.ahead, T.leafFg, bold: false)
                        .help("\(slot.ahead) on this branch that main doesn't have")
                }
                if slot.unpushed > 0 {
                    count("↑", slot.unpushed, T.skyFg, bold: false)
                        .help("\(slot.unpushed) to push")
                }
            }
        }
    }

    private func count(_ glyph: String, _ value: Int, _ color: Color, bold: Bool) -> some View {
        Text(verbatim: "\(glyph)\(value)")
            .font(Fonts.mono(13, bold ? .semibold : .medium))
            .monospacedDigit()
            .foregroundStyle(color)
            .fixedSize()
    }
}

struct PRSummary: View {
    let slot: Slot
    @EnvironmentObject private var store: Store
    @State private var hover = false

    var body: some View {
        if let pr = slot.pr {
            Button {
                store.openPR(pr)
            } label: {
                HStack(spacing: 6) {
                    GitGlyph(kind: glyph(pr.status), color: tone(pr.status))
                    Text(verbatim: "#\(pr.number)")
                        .font(Fonts.mono(13))
                        .monospacedDigit()
                        .underline(hover, color: T.fg)
                        .foregroundStyle(T.fg)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .onHover { hover = $0 }
            .help("\(pr.status.label) · \(pr.title)")
            .accessibilityLabel("Pull request #\(pr.number), \(pr.status.label.lowercased())")
        } else {
            Text(slot.branch == nil ? "—" : "No pull request").font(.system(size: 14)).foregroundStyle(T.subtle)
                .fixedSize()
        }
    }

    private func glyph(_ status: PRStatus) -> GitGlyph.Kind {
        switch status {
        case .draft: return .draft
        case .merged: return .merge
        default: return .pullRequest
        }
    }

    private func tone(_ status: PRStatus) -> Color {
        switch status {
        case .draft, .closed: return T.muted
        case .open: return T.skyFg
        case .approved: return T.leafFg
        case .changes: return T.rubyFg
        case .merged: return T.pulseFg
        }
    }
}

/// One of the open-in buttons: its tile is muted at rest and takes its app's full colour under the pointer.
private struct OpenInButton<Glyph: View>: View {
    var tip: String
    var label: String
    var action: () -> Void
    @ViewBuilder var glyph: (Bool) -> Glyph
    @State private var hovered = false

    var body: some View {
        Button(action: action) { glyph(hovered) }
            .buttonStyle(.aurora(.outline, iconOnly: true))
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
            .tip(tip)
            .accessibilityLabel(label)
    }
}

/// A small app-icon tile with a white mark, so the open-in buttons read as one set.
private struct AppGlyph<Mark: View>: View {
    var color: Color
    @ViewBuilder var mark: Mark

    var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(color)
            .frame(width: 15, height: 15)
            .overlay(mark.foregroundColor(.white))
    }
}
