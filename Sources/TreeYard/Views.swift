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
        } else {
            ToolbarItem(placement: .navigation) { HeaderTitle() }
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
                        columns: [GridItem(.adaptive(minimum: 345, maximum: 520), spacing: 16)], spacing: 16
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
        items.append(MenuItem(title: "Refresh", icon: .symbol("arrow.clockwise"), action: { store.refreshNow() }))
        // The title bar is a separate view tree, so the menu is placed from the pointer's x.
        let x = NSApp.keyWindow?.mouseLocationOutsideOfEventStream.x ?? 240
        store.menu = MenuRequest(
            items: items, anchor: CGRect(x: max(x - 60, 12), y: 0, width: 0, height: 0), belowTitleBar: true)
    }
}

/// The repo, the latest commit on its main branch, and how long ago it landed.
struct MainStatus: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(spacing: 16) {
            GitGlyph(kind: .commit, size: 18, color: T.muted)
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
            if let date = store.mainDate {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(ago(date, now: context.date)).font(.system(size: 14)).foregroundStyle(T.muted).fixedSize()
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
