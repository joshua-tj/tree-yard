import AppKit
import Foundation

enum PRStatus: Equatable {
    case draft, open, approved, changes, merged, closed

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .open: return "Open"
        case .approved: return "Approved"
        case .changes: return "Changes requested"
        case .merged: return "Merged"
        case .closed: return "Closed"
        }
    }
}

struct PullRequest: Equatable {
    var number: Int
    var title: String
    var status: PRStatus
    var url: String
}

enum StackState: Equatable {
    case running, starting, stopping, stopped
}

/// One worktree in the pool.
struct Slot: Identifiable, Equatable {
    let id: String
    var path: String
    /// 1-based position in the pool, for `{index}` in command templates.
    var index = 1
    /// nil when HEAD is detached: the slot is free.
    var branch: String?
    var ahead = 0
    var behind = 0
    var tracked = 0
    var untracked = 0
    /// Commits on the branch that its upstream doesn't have yet. Zero when there is no upstream.
    var unpushed = 0
    var port: Int?
    var pr: PullRequest?
    var leaseHolder: String?

    /// The stack's services from `treeyard.json`, each up while its port is open.
    var services: [Service] = []

    var rebasing = false
    var starting = false
    var stopping = false
    var listening = false
    var processAlive = false

    var dirty: Int { tracked + untracked }

    var stack: StackState {
        if stopping { return .stopping }
        if starting { return .starting }
        return (port != nil ? listening : processAlive) ? .running : .stopped
    }
}

/// One process of a slot's dev stack, watched by its port.
struct Service: Equatable, Identifiable {
    var name: String
    var port: Int
    var up = false
    var id: String { name }
}

/// How a slot's branch takes in new commits from main.
enum UpdateMethod: String, CaseIterable {
    case rebase, merge

    var label: String { self == .rebase ? "Rebase" : "Merge" }
}

/// A terminal app Tree Yard knows how to open a folder in.
struct TerminalApp: Identifiable, Equatable {
    var id: String
    var name: String

    static let known = [
        TerminalApp(id: "com.mitchellh.ghostty", name: "Ghostty"),
        TerminalApp(id: "com.googlecode.iterm2", name: "iTerm2"),
        TerminalApp(id: "dev.warp.Warp-Stable", name: "Warp"),
        TerminalApp(id: "com.apple.Terminal", name: "Terminal"),
    ]

    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
    static var installed: [TerminalApp] { known.filter { $0.url != nil } }
}

/// Commits behind before the count is flagged as worth a rebase.
let staleAfter = 20

/// `treeyard.json` in the worktree directory: how to run things in this pool.
struct RootConfig: Equatable {
    static let fileName = "treeyard.json"

    var start: String?
    var stop: String?
    var port: String?
    var url: String?
    var release: String?
    var editor: String?
    /// Service names and port templates, in the order they are listed.
    var services: [ServiceTemplate] = []

    struct ServiceTemplate: Equatable {
        var name: String
        var port: String
    }

    static func load(root: URL) -> (config: RootConfig, error: String?) {
        let file = root.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: file) else { return (RootConfig(), nil) }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (RootConfig(), "\(fileName) is not a valid JSON object.")
        }
        func string(_ key: String) -> String? {
            if let s = json[key] as? String { return s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s }
            if let n = json[key] as? NSNumber { return n.stringValue }
            return nil
        }
        let services = (json["services"] as? [[String: Any]] ?? []).compactMap { entry -> ServiceTemplate? in
            guard let name = entry["name"] as? String else { return nil }
            let port = (entry["port"] as? String) ?? (entry["port"] as? NSNumber)?.stringValue
            return port.map { ServiceTemplate(name: name, port: $0) }
        }
        return (
            RootConfig(
                start: string("start"), stop: string("stop"), port: string("port"), url: string("url"),
                release: string("release"), editor: string("editor"), services: services),
            nil
        )
    }

    /// Fills `{slot}`, `{index}`, `{port}` and `{path}` for one slot.
    func expand(_ template: String, slot: Slot, shell: Bool) -> String {
        template
            .replacingOccurrences(of: "{slot}", with: slot.id)
            .replacingOccurrences(of: "{index}", with: String(slot.index))
            .replacingOccurrences(of: "{port}", with: slot.port.map(String.init) ?? "")
            .replacingOccurrences(of: "{path}", with: shell ? Shell.quote(slot.path) : slot.path)
    }

    func port(for slot: Slot) -> Int? {
        guard let port else { return nil }
        return Int(expand(port, slot: slot, shell: false).trimmingCharacters(in: .whitespaces))
    }

    func services(for slot: Slot, open ports: Set<Int>) -> [Service] {
        services.compactMap { template in
            Int(expand(template.port, slot: slot, shell: false).trimmingCharacters(in: .whitespaces)).map {
                Service(name: template.name, port: $0, up: ports.contains($0))
            }
        }
    }

    func url(for slot: Slot) -> URL? {
        if let url { return URL(string: expand(url, slot: slot, shell: false)) }
        return slot.port.flatMap { URL(string: "http://localhost:\($0)") }
    }

    func environment(for slot: Slot) -> [String: String] {
        var env = ["TREEYARD_SLOT": slot.id, "TREEYARD_INDEX": String(slot.index), "TREEYARD_PATH": slot.path]
        if let port = slot.port { env["TREEYARD_PORT"] = String(port) }
        return env
    }
}

struct BranchOption: Identifiable, Equatable {
    var name: String
    var note: String
    var busy: Bool
    var id: String { name }
}

/// Read-only git and GitHub queries. Everything here is safe to run while agents work in the worktrees.
enum Git {
    struct Info {
        var branch: String?
        var tracked = 0
        var untracked = 0
        var ahead = 0
        var behind = 0
        var unpushed = 0
    }

    static func run(_ args: [String], at path: String, timeout: TimeInterval = 60) async -> CmdResult {
        await Shell.run(["git"] + args, cwd: path, env: ["GIT_OPTIONAL_LOCKS": "0"], timeout: timeout)
    }

    /// The pool's worktrees: each child folder that is a checkout, or holds exactly one.
    static func discover(_ root: URL) -> [(name: String, path: String)] {
        let fm = FileManager.default
        func isCheckout(_ url: URL) -> Bool { fm.fileExists(atPath: url.appendingPathComponent(".git").path) }
        func folders(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        return folders(root).compactMap { child in
            if isCheckout(child) { return (child.lastPathComponent, child.path) }
            if let inner = folders(child).first(where: isCheckout) { return (child.lastPathComponent, inner.path) }
            return nil
        }
    }

    /// One line of `git status --short`: the two-letter state, trimmed, and the path.
    struct Change: Equatable {
        var code: String
        var path: String
        var untracked: Bool { code == "??" }
    }

    static func changes(path: String) async -> [Change] {
        let result = await run(["status", "--porcelain"], at: path)
        guard result.ok else { return [] }
        return result.out.split(separator: "\n").compactMap { line in
            guard line.count > 3 else { return nil }
            return Change(
                code: line.prefix(2).trimmingCharacters(in: .whitespaces), path: String(line.dropFirst(3)))
        }
    }

    static func info(path: String, base: String) async -> Info? {
        async let statusResult = run(["status", "--porcelain=v2", "--branch"], at: path)
        async let countResult = run(["rev-list", "--left-right", "--count", "\(base)...HEAD"], at: path)
        let (status, count) = await (statusResult, countResult)
        guard status.ok else { return nil }
        var info = Info()
        for line in status.out.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                let head = String(line.dropFirst("# branch.head ".count))
                info.branch = head == "(detached)" ? nil : head
            } else if line.hasPrefix("# branch.ab ") {
                // "+<ahead of upstream> -<behind upstream>", present only when the branch has an upstream.
                let ahead = line.dropFirst("# branch.ab ".count).split(separator: " ").first ?? ""
                info.unpushed = Int(ahead.dropFirst()) ?? 0
            } else if line.hasPrefix("? ") {
                info.untracked += 1
            } else if !line.hasPrefix("#") && !line.hasPrefix("!") {
                info.tracked += 1
            }
        }
        let parts = count.trimmed.split(whereSeparator: { $0 == "\t" || $0 == " " }).compactMap { Int($0) }
        if count.ok, parts.count == 2 {
            info.behind = parts[0]
            info.ahead = parts[1]
        }
        return info
    }

    /// `origin/main`, or whatever the remote's default branch is.
    static func defaultBase(path: String) async -> String {
        let head = await run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], at: path)
        if head.ok, !head.trimmed.isEmpty { return head.trimmed }
        // Only ever a remote-tracking ref: new branches start from origin, never from a local main.
        for candidate in ["origin/main", "origin/master"] {
            if await run(["rev-parse", "--verify", "--quiet", candidate], at: path).ok { return candidate }
        }
        return "origin/main"
    }

    /// `owner/name` from the origin URL.
    static func repoSlug(path: String) async -> String? {
        let url = await run(["remote", "get-url", "origin"], at: path).trimmed
        guard !url.isEmpty else { return nil }
        var tail = url
        if let r = tail.range(of: "://") { tail = String(tail[r.upperBound...]) }
        tail = tail.replacingOccurrences(of: ":", with: "/")
        if tail.hasSuffix(".git") { tail = String(tail.dropLast(4)) }
        let parts = tail.split(separator: "/")
        return parts.count >= 2 ? parts.suffix(2).joined(separator: "/") : nil
    }

    static func latestCommit(
        path: String, ref: String
    ) async -> (subject: String, date: Date, sha: String, author: String)? {
        let r = await run(["log", "-1", "--format=%s%x1f%ct%x1f%H%x1f%an", ref], at: path)
        let parts = r.trimmed.components(separatedBy: "\u{1f}")
        guard r.ok, parts.count == 4, let t = TimeInterval(parts[1]) else { return nil }
        return (parts[0], Date(timeIntervalSince1970: t), parts[2], parts[3])
    }

    /// The GitHub login and avatar of a commit's author, when the commit is on GitHub and maps to an account.
    static func author(sha: String, slug: String, path: String) async -> (login: String, avatar: URL)? {
        let r = await Shell.run(
            ["gh", "api", "repos/\(slug)/commits/\(sha)", "--jq", ".author | select(.) | .login, .avatar_url"],
            cwd: path, timeout: 30)
        let lines = r.trimmed.split(separator: "\n").map(String.init)
        guard r.ok, lines.count == 2, var parts = URLComponents(string: lines[1]), parts.host != nil else { return nil }
        parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: "s", value: "64")]
        return parts.url.map { (lines[0], $0) }
    }

    static func unpushedCount(path: String) async -> Int {
        Int(await run(["rev-list", "--count", "HEAD", "--not", "--remotes"], at: path).trimmed) ?? 0
    }

    /// Branch name to the path of the worktree that has it checked out.
    static func checkedOut(path: String) async -> [String: String] {
        let r = await run(["worktree", "list", "--porcelain"], at: path)
        var map: [String: String] = [:]
        var current = ""
        for line in r.out.split(separator: "\n") {
            if line.hasPrefix("worktree ") {
                current = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch refs/heads/") {
                map[String(line.dropFirst("branch refs/heads/".count))] = current
            }
        }
        return map
    }

    /// Local and origin branches, most recently committed first.
    static func branches(path: String, slots: [Slot]) async -> [BranchOption] {
        async let refsResult = run(
            [
                "for-each-ref", "--sort=-committerdate", "--count=600",
                "--format=%(refname)%1f%(authorname)%1f%(committerdate:unix)", "refs/heads", "refs/remotes/origin",
            ], at: path)
        async let meResult = run(["config", "user.name"], at: path)
        async let checkedOutResult = checkedOut(path: path)
        let (refs, me, checkedOut) = await (refsResult, meResult.trimmed, checkedOutResult)
        var seen = Set<String>()
        var options: [BranchOption] = []
        for line in refs.out.split(separator: "\n") {
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count == 3 else { continue }
            var name = f[0]
            if name.hasPrefix("refs/heads/") {
                name = String(name.dropFirst("refs/heads/".count))
            } else if name.hasPrefix("refs/remotes/origin/") {
                name = String(name.dropFirst("refs/remotes/origin/".count))
            } else {
                continue
            }
            guard name != "HEAD", seen.insert(name).inserted else { continue }
            var note = f[1] == me && !me.isEmpty ? "You" : f[1]
            if let t = TimeInterval(f[2]) { note += " · " + ago(Date(timeIntervalSince1970: t)) }
            var busy = false
            if let holder = checkedOut[name] {
                busy = true
                if let slot = slots.first(where: { $0.path == holder }) {
                    note = "checked out in slot \(slot.id)"
                } else {
                    note = "checked out in \(URL(fileURLWithPath: holder).lastPathComponent)"
                }
            }
            options.append(BranchOption(name: name, note: note, busy: busy))
        }
        return options
    }

    static func pullRequest(branch: String, path: String) async -> PullRequest? {
        let r = await Shell.run(
            [
                "gh", "pr", "list", "--head", branch, "--state", "all", "--limit", "5", "--json",
                "number,title,state,isDraft,reviewDecision,url",
            ], cwd: path, timeout: 30)
        guard r.ok, let list = (try? JSONSerialization.jsonObject(with: Data(r.out.utf8))) as? [[String: Any]]
        else { return nil }
        guard let pr = list.first(where: { $0["state"] as? String == "OPEN" }) ?? list.first,
            let number = pr["number"] as? Int
        else { return nil }
        let status: PRStatus
        switch pr["state"] as? String {
        case "MERGED": status = .merged
        case "CLOSED": status = .closed
        default:
            if pr["isDraft"] as? Bool == true {
                status = .draft
            } else if pr["reviewDecision"] as? String == "APPROVED" {
                status = .approved
            } else if pr["reviewDecision"] as? String == "CHANGES_REQUESTED" {
                status = .changes
            } else {
                status = .open
            }
        }
        return PullRequest(
            number: number, title: pr["title"] as? String ?? "", status: status, url: pr["url"] as? String ?? "")
    }

    /// Ports with a TCP listener on this machine.
    static func listeningPorts() async -> Set<Int> {
        let r = await Shell.run(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fn"], timeout: 10)
        var ports = Set<Int>()
        for line in r.out.split(separator: "\n") where line.hasPrefix("n") {
            if let colon = line.lastIndex(of: ":"), let port = Int(line[line.index(after: colon)...]) {
                ports.insert(port)
            }
        }
        return ports
    }

    /// Who holds each slot, when the directory is a treehouse pool.
    static func leases(root: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("treehouse-state.json")),
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let worktrees = json["worktrees"] as? [[String: Any]]
        else { return [:] }
        var map: [String: String] = [:]
        for w in worktrees where w["leased"] as? Bool == true {
            if let name = w["name"] as? String { map[name] = w["lease_holder"] as? String ?? "someone" }
        }
        return map
    }
}
