import AppKit
import SwiftUI

enum ActiveDialog: Equatable {
    case changeBranch(String)
    case newBranch(String)
    case release(String)
    case setup
    case settings
}

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

@MainActor
final class Store: ObservableObject {
    @Published var root: URL?
    @Published var recents: [String] = []
    @Published var slots: [Slot] = []
    @Published var loaded = false
    @Published var repoSlug: String?
    /// Whether origin is on GitHub, which is where the avatars come from.
    @Published var onGitHub = false
    @Published var base = "origin/main"
    @Published var mainSubject: String?
    @Published var mainDate: Date?
    @Published var mainAuthor: String?
    @Published var mainAvatar: URL?
    @Published var mainLogin: String?
    private var mainSha: String?
    @Published var fetching = false
    @Published var refreshing = false
    @Published var config = RootConfig()
    @Published var configError: String?
    @Published var dialog: ActiveDialog?
    @Published var alert: AlertInfo?
    @Published var menu: MenuRequest?
    #if DEBUG
    /// A line of text over the window, set by a script's `caption:` step for demo videos.
    @Published var caption: String?
    #endif

    /// Settings, kept in the app's preferences. An empty terminal means the first one installed.
    @Published var terminal: String { didSet { defaults.set(terminal, forKey: "terminal") } }
    @Published var updateMethod: UpdateMethod { didSet { defaults.set(updateMethod.rawValue, forKey: "updateMethod") } }

    private var loop: Task<Void, Never>?
    private var generation = 0
    private var pids: [String: pid_t] = [:]
    private var watchers: [String: DispatchSourceProcess] = [:]
    private var startDeadlines: [String: Date] = [:]
    private var prCache: [String: PullRequest] = [:]

    private let defaults = UserDefaults.standard

    /// The repo as the header shows it.
    /// The GitHub avatar of the repo's owner, a person or an organisation.
    var ownerAvatar: URL? {
        guard onGitHub, let owner = repoSlug?.split(separator: "/").first else { return nil }
        return URL(string: "https://github.com/\(owner).png?size=64")
    }

    var repoName: String { repoSlug ?? root?.lastPathComponent ?? "" }
    /// `main`, for labels.
    var baseName: String { base.hasPrefix("origin/") ? String(base.dropFirst(7)) : base }

    #if DEBUG
    private static let scripted = ["TREEYARD_SCRIPT", "TREEYARD_SNAPSHOT", "TREEYARD_RECORD"].contains {
        ProcessInfo.processInfo.environment[$0] != nil
    }
    #else
    private static let scripted = false
    #endif

    init() {
        terminal = defaults.string(forKey: "terminal") ?? ""
        updateMethod = defaults.string(forKey: "updateMethod").flatMap(UpdateMethod.init) ?? .rebase
        recents = defaults.stringArray(forKey: "recentRoots") ?? []
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        var isDir: ObjCBool = false
        if let arg = args.first, FileManager.default.fileExists(atPath: arg, isDirectory: &isDir), isDir.boolValue {
            open(URL(fileURLWithPath: arg))
        } else if let last = defaults.string(forKey: "root"), FileManager.default.fileExists(atPath: last) {
            open(URL(fileURLWithPath: last))
        }
        #if DEBUG
            if let script = ProcessInfo.processInfo.environment["TREEYARD_SCRIPT"] { Task { await run(script: script) } }
        #endif
    }

    #if DEBUG
    /// Development aid: drives the store without the pointer, e.g. `start:1,sleep:8,stop:1`.
    private func run(script: String) async {
        while !loaded { try? await Task.sleep(nanoseconds: 200_000_000) }
        for step in script.split(separator: ",") {
            let p = step.split(separator: ":", maxSplits: 2).map(String.init)
            DemoRecorder.mark(String(step))
            switch p[0] {
            // "fast" waits like "sleep", and marks the wait as one a demo video should speed through.
            case "sleep", "fast": try? await Task.sleep(nanoseconds: UInt64((Double(p[1]) ?? 1) * 1e9))
            case "caption": caption = p.count > 1 ? p.dropFirst().joined(separator: ":") : nil
            case "refresh": refreshNow()
            case "close":
                menu = nil
                dialog = nil
            case "quit":
                DemoRecorder.mark("end")
                NSApp.terminate(nil)
            case "start": start(p[1])
            case "stop": await stop(p[1])
            case "rebase": rebase(p[1])
            case "install": install(p[1])
            case "refreshing": refreshing = true
            case "switch": _ = await changeBranch(p[1], to: p[2], create: false)
            case "create": _ = await changeBranch(p[1], to: p[2], create: true)
            case "release": _ = await release(p[1])
            case "menu":
                let window = NSApp.windows.first { $0.isVisible }
                let size = window?.contentView?.bounds.size ?? .zero
                if p[1] == "services", let slot = slots.first {
                    menu = MenuRequest(
                        items: slot.services.map {
                            MenuItem(title: $0.name, icon: .dot($0.up ? T.leafFg : T.subtle), detail: ":\($0.port)")
                        } + [.divider, MenuItem(title: "Show start log", icon: .symbol("doc.text"))],
                        anchor: CGRect(x: size.width / 2, y: 120, width: 0, height: 0), alignTrailing: true)
                } else if p[1] == "header" {
                    menu = MenuRequest(
                        items: recents.map { MenuItem(title: $0, icon: .symbol("folder"), checked: $0 == root?.path) }
                            + [.divider, MenuItem(title: "Open directory…", icon: .symbol("folder.badge.plus")),
                               MenuItem(title: "Refresh", icon: .symbol("arrow.clockwise"))],
                        anchor: CGRect(x: 230, y: 0, width: 0, height: 0), belowTitleBar: true)
                } else {
                    menu = MenuRequest(
                        items: [
                            MenuItem(title: "Change branch…", icon: .branch),
                            MenuItem(title: "Show in Finder", icon: .symbol("folder")), .divider,
                            MenuItem(title: "Release slot…", icon: .symbol("rectangle.portrait.and.arrow.right"), destructive: true),
                        ],
                        anchor: CGRect(x: size.width / 2 - 28, y: 388, width: 28, height: 28), alignTrailing: true)
                }
            case "dialog":
                dialog =
                    p[1] == "branch" ? .changeBranch(p[2]) : p[1] == "new" ? .newBranch(p[2])
                    : p[1] == "release" ? .release(p[2]) : p[1] == "settings" ? .settings : .setup
            default: break
            }
            NSLog("treeyard script: %@ -> %@", String(step), slots.map { "\($0.id):\($0.branch ?? "-"):\($0.stack)" }.joined(separator: " "))
            if let alert { NSLog("treeyard alert: %@ | %@", alert.title, alert.message) }
        }
    }
    #endif

    // MARK: Choosing the directory

    func pickRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Open"
        panel.message = "Choose the folder that holds your worktrees"
        if let root { panel.directoryURL = root.deletingLastPathComponent() }
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        let url = url.standardizedFileURL
        generation += 1
        loop?.cancel()
        root = url
        slots = []
        loaded = false
        repoSlug = nil
        onGitHub = false
        mainSubject = nil
        mainDate = nil
        mainAuthor = nil
        mainAvatar = nil
        mainLogin = nil
        mainSha = nil
        config = RootConfig()
        configError = nil
        dialog = nil
        prCache = [:]
        pids = [:]
        watchers.values.forEach { $0.cancel() }
        watchers = [:]

        recents = ([url.path] + recents.filter { $0 != url.path }).prefix(8).map { $0 }
        // A scripted or recorded run leaves no trace, so it never changes which directory the app opens next.
        if !Self.scripted {
            defaults.set(url.path, forKey: "root")
            defaults.set(recents, forKey: "recentRoots")
        }

        loop = Task { [weak self] in
            await self?.bootstrap()
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let self else { return }
                tick += 1
                await self.refreshPorts()
                if tick % 5 == 0 { await self.refreshGit() }
                if tick % 40 == 0 { Task { await self.refreshPRs() } }
                if tick % 100 == 0 { Task { await self.fetch() } }
            }
        }
    }

    /// A refresh the user asked for. `refreshing` stays on long enough for the button's spin to be seen.
    func refreshNow() {
        guard !refreshing, root != nil else { return }
        refreshing = true
        Task {
            async let floor: Void? = try? Task.sleep(nanoseconds: 700_000_000)
            await fetch()
            await refreshPRs()
            _ = await floor
            refreshing = false
        }
    }

    // MARK: Reading state

    private func bootstrap() async {
        guard let root else { return }
        let gen = generation
        if let first = Git.discover(root).first {
            async let baseResult = Git.defaultBase(path: first.path)
            async let slugResult = Git.repoSlug(path: first.path)
            let (base, slug) = await (baseResult, slugResult)
            guard gen == generation else { return }
            self.base = base
            self.repoSlug = slug
            self.onGitHub = await Git.run(["remote", "get-url", "origin"], at: first.path).out.contains("github.com")
        }
        await refreshGit()
        await refreshPorts()
        guard gen == generation else { return }
        Task { await self.refreshPRs() }
        Task { await self.fetch() }
    }

    func refreshGit() async {
        guard let root else { return }
        let gen = generation
        let base = self.base
        let found = Git.discover(root)
        let (config, configError) = RootConfig.load(root: root)
        let leases = Git.leases(root: root)

        let infos = await withTaskGroup(of: (String, Git.Info?).self) { group -> [String: Git.Info] in
            for f in found { group.addTask { (f.name, await Git.info(path: f.path, base: base)) } }
            var result: [String: Git.Info] = [:]
            for await (name, info) in group { result[name] = info }
            return result
        }
        let main: (subject: String, date: Date, sha: String, author: String)?
        if let first = found.first { main = await Git.latestCommit(path: first.path, ref: base) } else { main = nil }
        guard gen == generation else { return }

        var next: [Slot] = []
        var branchChanged = false
        for (i, f) in found.enumerated() {
            guard let info = infos[f.name] else { continue }
            var slot = slots.first { $0.id == f.name } ?? Slot(id: f.name, path: f.path)
            if slot.branch != info.branch || slot.path != f.path {
                slot.pr = info.branch.flatMap { prCache[$0] }
                branchChanged = branchChanged || loaded
            }
            slot.path = f.path
            slot.index = i + 1
            slot.branch = info.branch
            slot.ahead = info.ahead
            slot.behind = info.behind
            slot.tracked = info.tracked
            slot.untracked = info.untracked
            slot.unpushed = info.unpushed
            slot.leaseHolder = leases[f.name]
            slot.port = config.port(for: slot)
            next.append(slot)
        }
        if self.config != config { self.config = config }
        if self.configError != configError { self.configError = configError }
        if slots != next { slots = next }
        if let main {
            if mainSubject != main.subject { mainSubject = main.subject }
            if mainDate != main.date { mainDate = main.date }
            if mainAuthor != main.author { mainAuthor = main.author }
            // Looked up once per commit, as soon as the repo's GitHub name is known.
            if mainSha != main.sha, onGitHub, let slug = repoSlug, let path = next.first?.path {
                mainSha = main.sha
                Task {
                    let author = await Git.author(sha: main.sha, slug: slug, path: path)
                    if mainSha == main.sha {
                        mainAvatar = author?.avatar
                        mainLogin = author?.login
                    }
                }
            }
        }
        loaded = true
        if branchChanged { Task { await self.refreshPRs() } }
    }

    func refreshPorts() async {
        let gen = generation
        let watching = !config.services.isEmpty || slots.contains { $0.port != nil }
        let ports = watching ? await Git.listeningPorts() : []
        guard gen == generation else { return }
        var next = slots
        for i in next.indices {
            let id = next[i].id
            next[i].listening = next[i].port.map(ports.contains) ?? false
            next[i].services = config.services(for: next[i], open: ports)
            next[i].processAlive = pids[id].map { kill($0, 0) == 0 } ?? false
            if next[i].starting {
                let up = next[i].port != nil ? next[i].listening : false
                let expired = startDeadlines[id].map { $0 < Date() } ?? false
                if up || expired {
                    next[i].starting = false
                    startDeadlines[id] = nil
                }
            }
        }
        if slots != next { slots = next }
    }

    func refreshPRs() async {
        let gen = generation
        let targets = slots.compactMap { slot in slot.branch.map { (branch: $0, path: slot.path) } }
        guard !targets.isEmpty else { return }
        let found = await withTaskGroup(of: (String, PullRequest?).self) { group -> [String: PullRequest] in
            for t in targets { group.addTask { (t.branch, await Git.pullRequest(branch: t.branch, path: t.path)) } }
            var result: [String: PullRequest] = [:]
            for await (branch, pr) in group { if let pr { result[branch] = pr } }
            return result
        }
        guard gen == generation else { return }
        for t in targets { prCache[t.branch] = found[t.branch] }
        var next = slots
        for i in next.indices { next[i].pr = next[i].branch.flatMap { found[$0] } }
        if slots != next { slots = next }
    }

    func fetch() async {
        guard !fetching, let path = slots.first?.path else { return }
        fetching = true
        _ = await Git.run(["fetch", "origin", "--quiet"], at: path, timeout: 180)
        fetching = false
        await refreshGit()
    }

    private func update(_ id: String, _ change: (inout Slot) -> Void) {
        guard let i = slots.firstIndex(where: { $0.id == id }) else { return }
        change(&slots[i])
    }

    private func slot(_ id: String) -> Slot? { slots.first { $0.id == id } }

    private func fail(_ title: String, _ result: CmdResult) {
        let lines = result.message.split(separator: "\n", omittingEmptySubsequences: false).suffix(14)
        alert = AlertInfo(title: title, message: lines.joined(separator: "\n"))
    }

    // MARK: The dev stack

    func toggleStack(_ id: String) {
        guard let slot = slot(id) else { return }
        switch slot.stack {
        case .stopped: start(id)
        // Stop also works while starting, so a boot that never opens its port can be cancelled.
        case .running, .starting: Task { await stop(id) }
        case .stopping: break
        }
    }

    private func logURL(for slot: Slot) -> URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/TreeYard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(root?.lastPathComponent ?? "pool")-\(slot.id).log")
    }

    func start(_ id: String) {
        guard let slot = slot(id) else { return }
        guard let template = config.start else {
            dialog = .setup
            return
        }
        update(id) { $0.starting = true }
        startDeadlines[id] = nil
        let command = config.expand(template, slot: slot, shell: true)
        let log = logURL(for: slot)
        let extra = config.environment(for: slot)
        let gen = generation
        Task {
            let env = await Shell.env(adding: extra)
            guard gen == generation else { return }
            guard let pid = Shell.spawnDetached(command: command, cwd: slot.path, env: env, log: log.path) else {
                update(id) { $0.starting = false }
                alert = AlertInfo(title: "Couldn't start slot \(id)", message: "The start command could not be launched.")
                return
            }
            pids[id] = pid
            if slot.port == nil { startDeadlines[id] = Date().addingTimeInterval(2) }
            watch(pid, slot: id, log: log)
        }
    }

    /// Reaps the start command when it exits, and reports a failed boot.
    private func watch(_ pid: pid_t, slot id: String, log: URL) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        let gen = generation
        source.setEventHandler { [weak self] in
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            source.cancel()
            let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            Task { @MainActor in
                guard let self, gen == self.generation, self.pids[id] == pid else { return }
                self.pids[id] = nil
                self.watchers[id] = nil
                guard let slot = self.slot(id), slot.starting else { return }
                if code != 0 {
                    self.update(id) { $0.starting = false }
                    let tail = (try? String(contentsOf: log, encoding: .utf8))?
                        .split(separator: "\n").suffix(12).joined(separator: "\n")
                    self.alert = AlertInfo(
                        title: "Slot \(id) didn't start",
                        message: "The start command exited with code \(code).\n\n\(tail ?? "")\n\nLog: \(log.path)")
                } else {
                    // The command handed off to a daemon; give the port a while to open.
                    self.startDeadlines[id] = Date().addingTimeInterval(slot.port == nil ? 0 : 90)
                }
            }
        }
        watchers[id] = source
        source.resume()
    }

    func stop(_ id: String) async {
        guard let slot = slot(id), !slot.stopping else { return }
        update(id) {
            $0.stopping = true
            $0.starting = false
        }
        let gen = generation
        if let template = config.stop {
            let result = await Shell.sh(
                config.expand(template, slot: slot, shell: true), cwd: slot.path,
                env: config.environment(for: slot), timeout: 90)
            if !result.ok, gen == generation { fail("The stop command failed for slot \(id)", result) }
        }
        if let pid = pids[id], kill(pid, 0) == 0 {
            kill(-pid, SIGTERM)
        } else if config.stop == nil, let port = slot.port {
            // Not ours to signal by group (started elsewhere, or before a relaunch): stop the port's listeners.
            let owners = await Shell.run(["lsof", "-nP", "-t", "-iTCP:\(port)", "-sTCP:LISTEN"], timeout: 10)
            for pid in owners.out.split(separator: "\n").compactMap({ pid_t($0) }) { kill(pid, SIGTERM) }
        }
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard gen == generation else { return }
            let alive = pids[id].map { kill($0, 0) == 0 } ?? false
            let listening = slot.port != nil ? await Git.listeningPorts().contains(slot.port!) : false
            if !alive && !listening { break }
        }
        guard gen == generation else { return }
        update(id) {
            $0.stopping = false
            $0.listening = false
            $0.processAlive = false
        }
        await refreshPorts()
    }

    // MARK: Git actions

    func rebase(_ id: String) {
        guard let slot = slot(id), slot.branch != nil, !slot.rebasing else { return }
        update(id) { $0.rebasing = true }
        let base = self.base
        let method = updateMethod
        Task {
            if base.hasPrefix("origin/") {
                _ = await Git.run(["fetch", "origin", String(base.dropFirst(7)), "--quiet"], at: slot.path, timeout: 180)
            }
            let verb = method.rawValue
            let result = await Git.run([verb, "--autostash", base], at: slot.path, timeout: 300)
            if !result.ok {
                _ = await Git.run([verb, "--abort"], at: slot.path)
                fail("\(method.label) stopped on conflicts and was aborted", result)
            } else if (result.out + result.err).contains("autostash resulted in conflicts") {
                alert = AlertInfo(
                    title: "\(method == .rebase ? "Rebased" : "Merged into") slot \(id), but your uncommitted changes conflict",
                    message: "They could not be reapplied cleanly and are still in the stash. See `git stash list` in the worktree.")
            }
            update(id) { $0.rebasing = false }
            await refreshGit()
        }
    }

    /// Installs the worktree's dependencies with the pool's "install" command.
    func install(_ id: String) {
        guard let slot = slot(id), !slot.installing, let template = config.install else { return }
        let command = config.expand(template, slot: slot, shell: true)
        update(id) { $0.installing = true }
        Task {
            let result = await Shell.sh(command, cwd: slot.path, env: config.environment(for: slot), timeout: 1800)
            update(id) { $0.installing = false }
            if !result.ok { fail("Installing dependencies failed in slot \(id)", result) }
            await refreshGit()
        }
    }

    /// Stashes tracked changes, switches (or creates) the branch, and restarts a running stack.
    func changeBranch(_ id: String, to branch: String, create: Bool) async -> Bool {
        guard let slot = slot(id) else { return false }
        if slot.tracked > 0 {
            let label = "tree-yard: \(slot.branch ?? "detached") in slot \(id)"
            let stash = await Git.run(["stash", "push", "-m", label], at: slot.path)
            guard stash.ok else {
                fail("Couldn't stash changes in slot \(id)", stash)
                return false
            }
        }
        if create, base.hasPrefix("origin/") {
            // Start from origin's main as it is now, not as of the last background fetch.
            _ = await Git.run(["fetch", "origin", String(base.dropFirst(7)), "--quiet"], at: slot.path, timeout: 180)
        }
        let args = create ? ["switch", "-c", branch, "--no-track", base] : ["switch", branch]
        let result = await Git.run(args, at: slot.path, timeout: 180)
        guard result.ok else {
            fail("Couldn't switch slot \(id) to \(branch)", result)
            await refreshGit()
            return false
        }
        await refreshGit()
        if slot.stack == .running || slot.stack == .starting {
            await stop(id)
            start(id)
        }
        return true
    }

    /// Stops the stack and frees the slot: the pool's release command, or stash and detach at the base.
    func release(_ id: String) async -> Bool {
        guard let slot = slot(id) else { return false }
        if slot.stack != .stopped { await stop(id) }
        if let template = config.release {
            let result = await Shell.sh(
                config.expand(template, slot: slot, shell: true), cwd: root?.path,
                env: config.environment(for: slot), timeout: 180)
            guard result.ok else {
                fail("The release command failed for slot \(id)", result)
                await refreshGit()
                return false
            }
        } else {
            if slot.tracked > 0 {
                let label = "tree-yard: released \(slot.branch ?? "detached") from slot \(id)"
                let stash = await Git.run(["stash", "push", "-m", label], at: slot.path)
                guard stash.ok else {
                    fail("Couldn't stash changes in slot \(id)", stash)
                    return false
                }
            }
            let result = await Git.run(["switch", "--detach", base], at: slot.path, timeout: 180)
            guard result.ok else {
                fail("Couldn't release slot \(id)", result)
                await refreshGit()
                return false
            }
        }
        await refreshGit()
        return true
    }

    // MARK: Opening things

    func openEditor(_ id: String) {
        guard let slot = slot(id) else { return }
        if let template = config.editor {
            Task { _ = await Shell.sh(config.expand(template, slot: slot, shell: true), cwd: slot.path) }
            return
        }
        let folder = URL(fileURLWithPath: slot.path)
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            Task {
                let result = await Shell.run(["code", slot.path])
                if !result.ok { fail("Couldn't open VS Code", result) }
            }
        }
    }

    /// Opens a terminal window in the worktree: the one chosen in Settings, or the first installed.
    func openTerminal(_ id: String) {
        guard let slot = slot(id) else { return }
        let chosen = TerminalApp.known.first { $0.id == terminal }
        if let chosen, chosen.url == nil {
            alert = AlertInfo(
                title: "\(chosen.name) isn't installed",
                message: "Install it, or pick another terminal in Settings.")
            return
        }
        guard let app = (chosen ?? TerminalApp.installed.first)?.url else { return }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: slot.path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The installed Claude app's own icon, read from the app so the artwork isn't shipped here.
    static let claudeIcon: NSImage? = URL(string: "claude://code").flatMap {
        NSWorkspace.shared.urlForApplication(toOpen: $0)
    }.map { NSWorkspace.shared.icon(forFile: $0.path) }

    /// The same icon with half its colour, for the button at rest.
    static let claudeIconMuted: NSImage? = claudeIcon.flatMap { icon in
        let side = 128
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let cg = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
            let filter = CIFilter(name: "CIColorControls", parameters: [
                kCIInputImageKey: CIImage(cgImage: cg), kCIInputSaturationKey: 0.5,
            ]),
            let output = filter.outputImage,
            let gray = CIContext().createCGImage(output, from: output.extent)
        else { return icon }
        return NSImage(cgImage: gray, size: NSSize(width: side, height: side))
    }

    /// Starts a Claude Code session in the worktree through the desktop app's deep link.
    func openClaude(_ id: String) {
        guard let slot = slot(id) else { return }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let folder = slot.path.addingPercentEncoding(withAllowedCharacters: allowed),
            let url = URL(string: "claude://code/new?folder=\(folder)")
        else { return }
        if NSWorkspace.shared.urlForApplication(toOpen: url) == nil {
            alert = AlertInfo(
                title: "Couldn't open Claude Code", message: "No app on this Mac handles claude:// links.")
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func openStack(_ id: String) {
        guard let slot = slot(id), let url = config.url(for: slot) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the slot's start log, where a service that failed to boot says why.
    func openLog(_ id: String) {
        guard let slot = slot(id) else { return }
        let log = logURL(for: slot)
        if FileManager.default.fileExists(atPath: log.path) {
            NSWorkspace.shared.open(log)
        } else {
            alert = AlertInfo(
                title: "No log for slot \(id)", message: "Tree Yard only has a log for stacks it started itself.")
        }
    }

    func openPR(_ pr: PullRequest) {
        if let url = URL(string: pr.url) { NSWorkspace.shared.open(url) }
    }

    func revealInFinder(_ id: String) {
        guard let slot = slot(id) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: slot.path)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// What to hand a coding agent so it writes `treeyard.json` for this pool.
    var setupPrompt: String {
        let rootPath = root?.path ?? "<worktree directory>"
        let example = slots.first?.path ?? "\(rootPath)/1"
        return """
            Set up Tree Yard's Run and Stop buttons for the worktree pool at \(rootPath).

            Tree Yard is a Mac app that shows each worktree in that folder as a numbered slot. It reads \
            \(rootPath)/\(RootConfig.fileName), a JSON object with these keys, all optional:

            - "start": shell command that starts the dev stack. Runs with zsh in the slot's worktree and keeps running in the foreground.
            - "stop": shell command that stops it, run in the same worktree. Without it, Tree Yard signals the start command's process group.
            - "port": the port the slot's main web server listens on. Tree Yard shows the slot as running while this port is open, and links to it.
            - "url": what the port link opens. Defaults to http://localhost:{port}.
            - "release": command that frees a slot, run in the pool folder. Without it, Tree Yard stashes tracked changes and detaches at the default branch.
            - "services": optional list of the stack's services, each {"name": "api", "port": "30{slot}1"}. Tree Yard shows which are up by their ports.
            - "install": command that installs dependencies, run in the worktree, such as "yarn install". The tile's install button only appears when this is set.
            - "editor": command that opens the worktree in an editor. Defaults to VS Code.

            Every value may use {slot} (the slot's folder name, such as 1), {index} (its 1-based position), {port} and \
            {path} (the worktree, already shell-quoted in commands). Commands also get TREEYARD_SLOT, TREEYARD_INDEX, \
            TREEYARD_PORT and TREEYARD_PATH in their environment.

            Read the repo in one worktree (for example \(example)): its README, package.json scripts, Makefile or \
            docker-compose file. Find how the dev stack starts and stops, and how each worktree gets its own ports so \
            two slots can run at once. Then write the file. Tree Yard picks it up within 15 seconds.

            Example:
            {
              "start": "PORT={port} npm run dev",
              "port": "30{slot}0"
            }
            """
    }
}
