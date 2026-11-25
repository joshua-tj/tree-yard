import SwiftUI

/// The scrim and the centred card, for whichever dialog is open.
struct DialogHost: View {
    let dialog: ActiveDialog
    @EnvironmentObject private var store: Store

    var body: some View {
        ZStack {
            T.scrim.onTapGesture { store.dialog = nil }
            Group {
                switch dialog {
                case .changeBranch(let id):
                    if let slot = store.slots.first(where: { $0.id == id }) { ChangeBranchDialog(slot: slot) }
                case .newBranch(let id):
                    if let slot = store.slots.first(where: { $0.id == id }) { NewBranchDialog(slot: slot) }
                case .release(let id):
                    if let slot = store.slots.first(where: { $0.id == id }) { ReleaseDialog(slot: slot) }
                case .setup:
                    SetupDialog()
                case .settings:
                    SettingsDialog()
                }
            }
            .padding(24)
        }
        .onExitCommand { store.dialog = nil }
    }
}

private struct DialogCard<Content: View>: View {
    var width: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(24)
            .frame(width: width, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(T.raised)
                    .shadow(color: .black.opacity(0.10), radius: 7, y: 6)
                    .shadow(color: .black.opacity(0.16), radius: 24, y: 18)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.line, lineWidth: 1))
            )
            .foregroundStyle(T.fg)
    }
}

private struct DialogTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 20, weight: .medium)).kerning(-0.2).fixedSize(horizontal: false, vertical: true)
    }
}

private struct Notice<Content: View>: View {
    var color: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) { content }
            .font(.system(size: 14))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
    }
}

private func mono(_ s: String) -> Text {
    Text(s).font(Fonts.mono(13)).foregroundColor(T.fg)
}

// MARK: Change branch

struct ChangeBranchDialog: View {
    let slot: Slot
    @EnvironmentObject private var store: Store
    @State private var query = ""
    @State private var picked: String?
    @State private var branches: [BranchOption]?
    @State private var working = false
    @FocusState private var searchFocused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var all: [BranchOption] { branches ?? [] }
    private var matches: [BranchOption] {
        let q = trimmed.lowercased()
        return Array((q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) }).prefix(60))
    }
    private var exact: Bool { all.contains { $0.name == trimmed } }
    private var canCreate: Bool { branches != nil && !trimmed.isEmpty && !exact && !trimmed.contains(" ") }
    private var target: String? { picked ?? (canCreate ? trimmed : nil) }
    private var isNew: Bool { target.map { t in !all.contains { $0.name == t } } ?? false }

    var body: some View {
        DialogCard(width: 448) {
            DialogTitle(
                text: slot.branch != nil ? "Change branch in slot \(slot.id)" : "Checkout a branch in slot \(slot.id)")
            Group {
                if let branch = slot.branch {
                    Text("Currently on ") + mono(branch) + Text(".")
                } else {
                    Text("The slot is free, with a detached HEAD.")
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(T.muted)
            .padding(.top, 6)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(T.muted)
                TextField("Find or create a branch", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                    .onSubmit(confirm)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(T.raised))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(searchFocused ? T.ring : T.matrixBorder, lineWidth: searchFocused ? 2 : 1)
            )
            .padding(.top, 16)

            ScrollView {
                VStack(spacing: 0) {
                    if branches == nil {
                        Text("Loading branches…").font(.system(size: 13)).foregroundStyle(T.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }
                    ForEach(matches) { branch in
                        BranchRow(active: picked == branch.name, disabled: branch.busy) {
                            picked = branch.name
                        } label: {
                            Text(branch.name).font(Fonts.mono(13)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 12)
                            Text(branch.note).font(.system(size: 12)).foregroundStyle(T.muted).lineLimit(1)
                                .layoutPriority(1)
                        }
                    }
                    if canCreate {
                        BranchRow(active: picked == trimmed, disabled: false) {
                            picked = trimmed
                        } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(T.muted)
                            (Text("Create ") + mono(trimmed) + Text(" from \(store.base)"))
                                .font(.system(size: 14)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(height: 256)
            .padding(.top, 12)

            if slot.tracked > 0 || slot.stack == .running {
                Notice(color: T.amberMuted) {
                    if slot.tracked > 0 {
                        Text(
                            "\(slot.tracked) uncommitted change\(slot.tracked == 1 ? "" : "s") will be stashed"
                                + (slot.branch.map { " on \($0)." } ?? "."))
                    }
                    if slot.stack == .running { Text("The dev stack restarts on the new branch.") }
                }
                .padding(.top, 12)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { store.dialog = nil }
                    .buttonStyle(.aurora(.outline, size: 2))
                    .keyboardShortcut(.cancelAction)
                Button(working ? "Switching…" : isNew ? "Create and switch" : "Switch branch", action: confirm)
                    .buttonStyle(.aurora(.solid, size: 2))
                    .disabled(target == nil || working)
            }
            .padding(.top, 24)
        }
        .task {
            searchFocused = true
            branches = await Git.branches(path: slot.path, slots: store.slots)
        }
        .onChange(of: query) { picked = nil }
    }

    private func confirm() {
        guard let target, !working else { return }
        working = true
        let create = isNew
        Task {
            if await store.changeBranch(slot.id, to: target, create: create) { store.dialog = nil }
            working = false
        }
    }
}

private struct BranchRow<Label: View>: View {
    var active: Bool
    var disabled: Bool
    var action: () -> Void
    @ViewBuilder var label: Label
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) { label }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? T.matrixMutedHover : hover && !disabled ? T.surface : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { hover = $0 }
    }
}

// MARK: New branch

/// Names a new branch and creates it from the base, straight from a free slot.
struct NewBranchDialog: View {
    let slot: Slot
    @EnvironmentObject private var store: Store
    @State private var name = ""
    @State private var working = false
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var valid: Bool { !trimmed.isEmpty && !trimmed.contains(" ") }

    var body: some View {
        DialogCard(width: 448) {
            DialogTitle(text: "New branch in slot \(slot.id)")
            (Text("Created from ") + mono(store.base) + Text(" and checked out here."))
                .font(.system(size: 14))
                .foregroundStyle(T.muted)
                .padding(.top, 6)

            HStack(spacing: 8) {
                GitGlyph(kind: .branch, color: T.muted)
                TextField("Branch name", text: $name)
                    .textFieldStyle(.plain)
                    .font(Fonts.mono(14))
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit(confirm)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(T.raised))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(focused ? T.ring : T.matrixBorder, lineWidth: focused ? 2 : 1)
            )
            .padding(.top, 16)

            if slot.tracked > 0 {
                Notice(color: T.amberMuted) {
                    Text("\(slot.tracked) uncommitted change\(slot.tracked == 1 ? "" : "s") will be stashed first.")
                }
                .padding(.top, 12)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { store.dialog = nil }
                    .buttonStyle(.aurora(.outline, size: 2))
                    .keyboardShortcut(.cancelAction)
                Button(working ? "Creating…" : "Create branch", action: confirm)
                    .buttonStyle(.aurora(.solid, size: 2))
                    .disabled(!valid || working)
            }
            .padding(.top, 24)
        }
        .task { focused = true }
    }

    private func confirm() {
        guard valid, !working else { return }
        working = true
        Task {
            if await store.changeBranch(slot.id, to: trimmed, create: true) { store.dialog = nil }
            working = false
        }
    }
}

// MARK: Release

struct ReleaseDialog: View {
    let slot: Slot
    @EnvironmentObject private var store: Store
    @State private var unpushed = 0
    @State private var changes: [Git.Change] = []
    @State private var working = false

    var body: some View {
        let custom = store.config.release
        DialogCard(width: 384) {
            DialogTitle(text: "Release slot \(slot.id)?")
            Group {
                if let branch = slot.branch {
                    Text(lead) + mono(branch) + Text(" stays in the repository.")
                } else {
                    Text(lead)
                }
            }
            .font(.system(size: 14))
            .lineSpacing(4)
            .foregroundStyle(T.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)

            if slot.dirty > 0 || unpushed > 0 || slot.leaseHolder != nil {
                Notice(color: T.rubyMuted) {
                    if custom != nil, slot.dirty > 0 {
                        Text("\(slot.dirty) uncommitted change\(slot.dirty == 1 ? "" : "s") will be discarded.")
                    } else if slot.tracked > 0 {
                        Text(
                            "\(slot.tracked) uncommitted change\(slot.tracked == 1 ? "" : "s") will be stashed. Untracked files stay."
                        )
                    }
                    if unpushed > 0 {
                        Text(
                            "\(unpushed) commit\(unpushed == 1 ? " is" : "s are") not on origin. Push before releasing to keep \(unpushed == 1 ? "it" : "them") safe."
                        )
                    }
                    if let holder = slot.leaseHolder {
                        Text("Leased by \(holder). Releasing ends the lease and whatever is running there.")
                    }
                }
                .padding(.top, 12)
            }

            if !changes.isEmpty {
                StatusList(changes: changes).padding(.top, 8)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { store.dialog = nil }
                    .buttonStyle(.aurora(.outline, size: 2))
                    .keyboardShortcut(.cancelAction)
                Button(working ? "Releasing…" : "Release slot") {
                    working = true
                    Task {
                        if await store.release(slot.id) { store.dialog = nil }
                        working = false
                    }
                }
                .buttonStyle(.aurora(.solid, tone: .ruby, size: 2))
                .disabled(working)
            }
            .padding(.top, 24)
        }
        .task { unpushed = slot.branch == nil ? 0 : await Git.unpushedCount(path: slot.path) }
        .task { if slot.dirty > 0 { changes = await Git.changes(path: slot.path) } }
    }

    private var lead: String {
        let stop = slot.stack != .stopped ? "Stops the dev stack, then " : ""
        if let custom = store.config.release {
            let command = store.config.expand(custom, slot: slot, shell: false)
            return (stop.isEmpty ? "Runs " : stop + "runs ") + "`\(command)` to return the slot to the pool. "
        }
        return (stop.isEmpty ? "Checks out " : stop + "checks out ") + "\(store.base) with a detached HEAD. "
    }
}

/// The worktree's `git status`, one file per row, scrolling once it gets long.
private struct StatusList: View {
    let changes: [Git.Change]
    private let rowHeight: CGFloat = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                    HStack(spacing: 8) {
                        Text(change.code)
                            .foregroundStyle(change.untracked ? T.subtle : T.rubyFg)
                            .frame(width: 18, alignment: .leading)
                        Text(change.path)
                            .foregroundStyle(change.untracked ? T.muted : T.fg)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(change.path)
                    }
                    .font(Fonts.mono(11))
                    .frame(height: rowHeight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .frame(height: min(CGFloat(changes.count), 8) * rowHeight + 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(T.surface))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.line))
        .accessibilityLabel("Uncommitted changes")
    }
}

// MARK: Settings

struct SettingsDialog: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let installed = TerminalApp.installed
        let chosen = TerminalApp.known.first { $0.id == store.terminal }
        DialogCard(width: 448) {
            DialogTitle(text: "Settings")

            SettingRow(
                title: "Terminal",
                detail: chosen == nil
                    ? "Opens \(installed.first?.name ?? "Terminal"), the first one installed."
                    : chosen?.url == nil
                        ? "\(chosen?.name ?? "This terminal") isn't installed on this Mac."
                        : "The terminal button opens the worktree here."
            ) {
                Segmented(
                    options: [("", "Automatic")] + TerminalApp.known.map { ($0.id, $0.name) }, selection: $store.terminal)
            }
            .padding(.top, 20)

            SettingRow(
                title: "Pull from main",
                detail: store.updateMethod == .rebase
                    ? "Replays the branch's commits on top of main. Rewrites history."
                    : "Merges main into the branch with a merge commit. Keeps history."
            ) {
                Segmented(
                    options: UpdateMethod.allCases.map { ($0, $0.label) }, selection: $store.updateMethod)
            }
            .padding(.top, 20)

            HStack {
                Spacer()
                Button("Done") { store.dialog = nil }
                    .buttonStyle(.aurora(.solid, size: 2))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 24)
        }
    }
}

private struct SettingRow<Control: View>: View {
    var title: String
    var detail: String
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .medium))
            control
            Text(detail).font(.system(size: 13)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A row of options where one is picked, in the design system's muted track.
private struct Segmented<Value: Hashable>: View {
    var options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: on ? .medium : .regular))
                        .foregroundStyle(on ? T.fg : T.muted)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(on ? T.raised : .clear)
                                .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(T.matrixMutedHover))
    }
}

// MARK: Setup

/// Shown when Run is pressed before the pool has a start command.
struct SetupDialog: View {
    @EnvironmentObject private var store: Store
    @State private var copied = false

    var body: some View {
        DialogCard(width: 448) {
            DialogTitle(text: "Tell Tree Yard how to run this repo")
            (Text("Run and Stop use the commands in ") + mono(RootConfig.fileName)
                + Text(" in the worktree directory. A coding agent can work them out from the repo and write the file."))
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(T.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Text(
                """
                {
                  "start": "PORT={port} npm run dev",
                  "stop": "npm run dev:kill",
                  "port": "30{slot}0"
                }
                """
            )
            .font(Fonts.mono(12))
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(T.surface))
            .padding(.top, 16)

            if let error = store.configError {
                Notice(color: T.rubyMuted) { Text(error) }.padding(.top, 12)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Done") { store.dialog = nil }
                    .buttonStyle(.aurora(.outline, size: 2))
                    .keyboardShortcut(.cancelAction)
                Button {
                    store.copy(store.setupPrompt)
                    copied = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 12, weight: .medium))
                        Text(copied ? "Copied" : "Copy prompt for an agent")
                    }
                }
                .buttonStyle(.aurora(.solid, size: 2))
            }
            .padding(.top, 24)
        }
    }
}
