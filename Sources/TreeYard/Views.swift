import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        ZStack {
            T.canvas
            SequoiaBackdrop()
            content
            if let dialog = store.dialog {
                DialogHost(dialog: dialog)
                    .transition(.opacity)
            }
            if let menu = store.menu {
                MenuLayer(request: menu) { store.menu = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.1), value: store.menu?.id)
        .overlay(alignment: .top) { Rectangle().fill(T.line).frame(height: 1) }
        .animation(.easeOut(duration: 0.18), value: store.dialog)
        .foregroundStyle(T.fg)
        .toolbar { header }
        .toolbarBackground(T.chrome, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .alert(item: $store.alert) { info in
            Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
    }

    /// The title sits straight on the chrome, without the glass capsule newer systems give toolbar items.
    @ToolbarContentBuilder private var header: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) { HeaderTitle() }.sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .primaryAction) { HeaderActions() }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { HeaderTitle() }
            ToolbarItem(placement: .primaryAction) {
                HStack { Spacer(); HeaderActions() }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if store.root == nil {
            Welcome()
        } else if !store.loaded {
            ProgressView().controlSize(.small)
        } else if store.slots.isEmpty {
            EmptyPool()
        } else {
            ScrollView {
                VStack(spacing: 24) {
                    MainStatus()
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 420), spacing: 16)], spacing: 16
                    ) {
                        ForEach(store.slots) { slot in SlotTile(slot: slot) }
                    }
                }
                .frame(maxWidth: 1136)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The window's title: the mark, "Worktrees", and the directory switcher.
struct HeaderTitle: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(spacing: 8) {
            TreeLogo()
            Text("Worktrees")
                .font(Fonts.display(17, weight: 600))
                .foregroundStyle(T.fg)
                .fixedSize()
            if store.root != nil {
                Text("/").foregroundStyle(T.subtle)
                Button(action: showMenu) {
                    HStack(spacing: 6) {
                        Text(store.repoName).font(Fonts.mono(12, .medium))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(.aurora(.ghost))
                .help(store.root?.path ?? "")
            }
        }
        .padding(.leading, 4)
    }

    private func showMenu() {
        var items = store.recents.map { path in
            MenuItem(
                title: (path as NSString).abbreviatingWithTildeInPath, icon: .symbol("folder"),
                checked: path == store.root?.path, action: { store.open(URL(fileURLWithPath: path)) })
        }
        items.append(.divider)
        items.append(MenuItem(title: "Open directory…", icon: .symbol("folder.badge.plus"), action: { store.pickRoot() }))
        // The title bar is a separate view tree, so the menu is placed from the pointer's x.
        let x = NSApp.keyWindow?.mouseLocationOutsideOfEventStream.x ?? 240
        store.menu = MenuRequest(
            items: items, anchor: CGRect(x: max(x - 60, 12), y: 0, width: 0, height: 0), belowTitleBar: true)
    }
}

/// Refresh and Settings, at the title bar's right edge.
struct HeaderActions: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(spacing: 4) {
            Button {
                store.refreshNow()
            } label: {
                RefreshGlyph(spinning: store.refreshing)
            }
            .buttonStyle(.aurora(.ghost, iconOnly: true))
            .disabled(store.root == nil)
            .tip(store.refreshing ? "Refreshing…" : "Refresh  ⌘R", below: true)
            .accessibilityLabel(store.refreshing ? "Refreshing" : "Refresh")

            Button {
                store.dialog = .settings
            } label: {
                Image(systemName: "gearshape").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.aurora(.ghost, iconOnly: true))
            .tip("Settings  ⌘,", below: true)
            .accessibilityLabel("Settings")
        }
        .padding(.trailing, 4)
    }
}

/// The refresh arrow. During a manual refresh it becomes a small orb of dots with drops falling through it.
private struct RefreshGlyph: View {
    var spinning: Bool

    var body: some View {
        if spinning {
            LoadingOrb().transition(.opacity)
        } else {
            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)).transition(.opacity)
        }
    }
}

/// The app's busy indicator: the rain orb, running. With reduced motion it holds still.
struct LoadingOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            RainOrb(time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
        }
    }
}

/// A 5×5 grid of dots with the corners cut to make a circle. A bright drop runs down each column
/// with a fading tail, each column out of step with the next.
private struct RainOrb: View {
    var time: TimeInterval

    private static let count = 5
    private static let offsets: [Double] = [0.0, 3.1, 1.3, 4.4, 2.2]
    private static let tail = 3.0

    var body: some View {
        Canvas { context, size in
            let step = size.width / CGFloat(Self.count)
            let dot = step * 0.62
            let cycle = Double(Self.count) + Self.tail
            for column in 0..<Self.count {
                let head = (time * 9 + Self.offsets[column]).truncatingRemainder(dividingBy: cycle)
                for row in 0..<Self.count {
                    if (column == 0 || column == Self.count - 1) && (row == 0 || row == Self.count - 1) { continue }
                    let behind = head - Double(row)
                    let glow = behind >= 0 && behind < Self.tail ? 1 - behind / Self.tail : 0
                    let rect = CGRect(
                        x: CGFloat(column) * step + (step - dot) / 2, y: CGFloat(row) * step + (step - dot) / 2,
                        width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(T.fg.opacity(0.16 + 0.84 * glow)))
                }
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// The repo, the latest commit on its main branch, and how long ago it landed.
struct MainStatus: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(spacing: 12) {
            if let owner = store.ownerAvatar {
                AsyncImage(url: owner) { image in
                    image.resizable().interpolation(.high)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(T.surface)
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(T.line))
                .accessibilityHidden(true)
            } else {
                GitGlyph(kind: .commit, size: 18, color: T.muted).frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store.repoName).font(Fonts.mono(12)).foregroundStyle(T.muted)
                Text(store.mainSubject ?? "No commits on \(store.base) yet")
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(store.fetching ? 0.5 : 1)
                    .animation(.easeOut(duration: 0.15), value: store.fetching)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                if let date = store.mainDate {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(ago(date, now: context.date) + (store.mainLogin == nil ? "" : " by"))
                            .font(.system(size: 14)).foregroundStyle(T.muted).fixedSize()
                    }
                }
                if let avatar = store.mainAvatar, let login = store.mainLogin {
                    AsyncImage(url: avatar) { image in
                        image.resizable().interpolation(.high)
                    } placeholder: {
                        Circle().fill(T.surface)
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(T.line))
                    .accessibilityHidden(true)
                    Text(login).font(Fonts.mono(12)).foregroundStyle(T.fg).fixedSize()
                        .help(store.mainAuthor ?? "")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(CardBackground())
        .accessibilityElement(children: .combine)
    }
}

struct Welcome: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(spacing: 0) {
            ClearingIllustration()
            Text("Choose a worktree directory")
                .font(Fonts.display(24, weight: 600))
                .padding(.top, 20)
            Text("Pick the folder that holds your worktrees, one in each subfolder.")
                .font(.system(size: 14))
                .foregroundStyle(T.muted)
                .padding(.top, 6)
            Button("Open Directory…") { store.pickRoot() }
                .buttonStyle(.aurora(.solid, size: 2))
                .padding(.top, 20)
        }
        .padding(40)
    }
}

struct EmptyPool: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(spacing: 0) {
            ClearingIllustration()
            Text("No worktrees here")
                .font(Fonts.display(24, weight: 600))
                .padding(.top, 20)
            Text((store.root?.path ?? "") + " has no git checkouts in its subfolders.")
                .font(.system(size: 14))
                .foregroundStyle(T.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Button("Open Another Directory…") { store.pickRoot() }
                .buttonStyle(.aurora(.outline, size: 2))
                .padding(.top, 20)
        }
        .padding(40)
    }
}
