import Foundation

struct CmdResult {
    var status: Int32
    var out: String
    var err: String
    var ok: Bool { status == 0 }
    var trimmed: String { out.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The most useful text to show when the command failed.
    var message: String {
        let e = err.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? trimmed : e
    }
}

enum Shell {
    /// The user's login-shell PATH, so git, gh, node and friends resolve as they do in a terminal.
    private static let environment: Task<[String: String], Never> = Task.detached {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        var parts: [String] = []
        let shell = env["SHELL"].flatMap { $0.hasSuffix("zsh") || $0.hasSuffix("bash") ? $0 : nil } ?? "/bin/zsh"
        let probe = runSync(shell, ["-ilc", "echo __TY__${PATH}__TY__"], cwd: nil, env: env, timeout: 8)
        let pieces = probe.out.components(separatedBy: "__TY__")
        if pieces.count >= 3 { parts += pieces[1].split(separator: ":").map(String.init) }
        parts += (env["PATH"] ?? "").split(separator: ":").map(String.init)
        parts += [
            "\(home)/.local/bin", "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin",
            "/usr/sbin", "/sbin",
        ]
        var seen = Set<String>()
        env["PATH"] = parts.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        env["GIT_TERMINAL_PROMPT"] = "0"
        return env
    }

    static func env(adding extra: [String: String] = [:]) async -> [String: String] {
        await environment.value.merging(extra) { _, new in new }
    }

    /// Runs a program found on PATH and collects its output.
    static func run(
        _ args: [String], cwd: String? = nil, env extra: [String: String] = [:], timeout: TimeInterval = 60
    ) async -> CmdResult {
        let env = await env(adding: extra)
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: runSync("/usr/bin/env", args, cwd: cwd, env: env, timeout: timeout))
            }
        }
    }

    /// Runs a shell command line.
    static func sh(
        _ command: String, cwd: String? = nil, env: [String: String] = [:], timeout: TimeInterval = 120
    ) async -> CmdResult {
        await run(["/bin/zsh", "-c", command], cwd: cwd, env: env, timeout: timeout)
    }

    private final class Buffer: @unchecked Sendable {
        var data = Data()
    }

    private static func runSync(
        _ exe: String, _ args: [String], cwd: String?, env: [String: String], timeout: TimeInterval
    ) -> CmdResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = env
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return CmdResult(status: 127, out: "", err: error.localizedDescription)
        }
        let outBuf = Buffer(), errBuf = Buffer()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outBuf.data = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errBuf.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        p.waitUntilExit()
        killer.cancel()
        // A grandchild can hold the pipes open after the command exits; don't wait on it forever.
        _ = group.wait(timeout: .now() + 2)
        return CmdResult(
            status: p.terminationStatus,
            out: String(decoding: outBuf.data, as: UTF8.self),
            err: String(decoding: errBuf.data, as: UTF8.self))
    }

    /// Starts a long-running command in its own process group, logging to a file, and returns its pid.
    /// The group outlives the app, and is what Stop signals.
    static func spawnDetached(command: String, cwd: String, env: [String: String], log: String) -> pid_t? {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, log, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        posix_spawn_file_actions_addchdir_np(&actions, cwd)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setpgroup(&attr, 0)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))

        let argv: [UnsafeMutablePointer<CChar>?] = ["/bin/zsh", "-c", command].map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        return posix_spawn(&pid, "/bin/zsh", &actions, &attr, argv, envp) == 0 ? pid : nil
    }

    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
