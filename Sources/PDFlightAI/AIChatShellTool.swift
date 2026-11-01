import Darwin
import Foundation

/// Runs an approved shell command in its own process group. Cancellation and
/// timeouts terminate that group so a stopped chat does not leave children.
public enum AIChatShellTool {
    public static func run(command: String, workingDirectory: URL, timeout: TimeInterval = 120) async -> AIChatToolResult {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, command.count <= 50_000 else {
            return AIChatToolResult(content: "命令为空或过长。", isError: true)
        }
        let state = ShellState()
        return await withTaskCancellationHandler {
            await Task.detached(priority: .utility) {
                execute(command: command, workingDirectory: workingDirectory, timeout: min(600, max(0.1, timeout)), state: state)
            }.value
        } onCancel: { state.cancel() }
    }

    private static func execute(command: String, workingDirectory: URL, timeout: TimeInterval, state: ShellState) -> AIChatToolResult {
        var stdoutPipe: [Int32] = [-1, -1]
        var stderrPipe: [Int32] = [-1, -1]
        guard pipe(&stdoutPipe) == 0 else { return AIChatToolResult(content: "无法创建命令输出管道。", isError: true) }
        guard pipe(&stderrPipe) == 0 else {
            close(stdoutPipe[0]); close(stdoutPipe[1])
            return AIChatToolResult(content: "无法创建命令错误输出管道。", isError: true)
        }
        defer { for fd in stdoutPipe + stderrPipe where fd >= 0 { close(fd) } }
        _ = fcntl(stdoutPipe[0], F_SETFL, O_NONBLOCK)
        _ = fcntl(stderrPipe[0], F_SETFL, O_NONBLOCK)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0, posix_spawnattr_init(&attributes) == 0 else {
            return AIChatToolResult(content: "无法初始化命令执行环境。", isError: true)
        }
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        let setup = [
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0),
            posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO),
            posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO),
            posix_spawn_file_actions_addclose(&actions, stdoutPipe[0]),
            posix_spawn_file_actions_addclose(&actions, stderrPipe[0]),
            posix_spawn_file_actions_addclose(&actions, stdoutPipe[1]),
            posix_spawn_file_actions_addclose(&actions, stderrPipe[1]),
            posix_spawn_file_actions_addchdir_np(&actions, workingDirectory.path),
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)),
            posix_spawnattr_setpgroup(&attributes, 0)
        ]
        guard setup.allSatisfy({ $0 == 0 }) else { return AIChatToolResult(content: "无法设置命令工作目录或进程组。", isError: true) }
        let args = ["/bin/bash", "-lc", command]
        let env = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        let argv = args.map { strdup($0) } + [nil]
        let envp = env.map { strdup($0) } + [nil]
        defer { for p in argv { free(p) }; for p in envp { free(p) } }
        var pid: pid_t = 0
        let result = argv.withUnsafeBufferPointer { argBuffer in
            envp.withUnsafeBufferPointer { envBuffer in
                posix_spawn(&pid, "/bin/bash", &actions, &attributes,
                            UnsafeMutablePointer(mutating: argBuffer.baseAddress!), UnsafeMutablePointer(mutating: envBuffer.baseAddress!))
            }
        }
        guard result == 0 else { return AIChatToolResult(content: "无法启动命令：\(String(cString: strerror(result)))", isError: true) }
        close(stdoutPipe[1]); stdoutPipe[1] = -1
        close(stderrPipe[1]); stderrPipe[1] = -1
        state.register(pid)
        defer { state.finish() }
        let deadline = Date().addingTimeInterval(timeout)
        var status: Int32 = 0
        var timedOut = false
        var stdout = Data(); var stderr = Data(); var stdoutTruncated = false; var stderrTruncated = false
        func drain(_ fd: Int32, into data: inout Data, truncated: inout Bool) {
            var bytes = [UInt8](repeating: 0, count: 8_192)
            for _ in 0..<128 {
                let count = Darwin.read(fd, &bytes, bytes.count)
                guard count > 0 else { break }
                let available = max(0, 64_000 - data.count)
                if available > 0 { data.append(contentsOf: bytes.prefix(min(available, count))) }
                if count > available { truncated = true }
            }
        }
        while true {
            drain(stdoutPipe[0], into: &stdout, truncated: &stdoutTruncated)
            drain(stderrPipe[0], into: &stderr, truncated: &stderrTruncated)
            let waited = state.poll(pid, status: &status)
            if waited == pid { break }
            if waited < 0 && errno != EINTR { return AIChatToolResult(content: "无法读取命令退出状态。", isError: true) }
            if Date() >= deadline && !state.isCancelled { timedOut = true; state.cancel() }
            usleep(50_000)
        }
        state.finish()
        drain(stdoutPipe[0], into: &stdout, truncated: &stdoutTruncated)
        drain(stderrPipe[0], into: &stderr, truncated: &stderrTruncated)
        let stdoutText = String(decoding: stdout, as: UTF8.self) + (stdoutTruncated ? "\n[输出已截断]" : "")
        let stderrText = String(decoding: stderr, as: UTF8.self) + (stderrTruncated ? "\n[输出已截断]" : "")
        let exitCode = (status & 0x7f) == 0 ? Int((status >> 8) & 0xff) : Int(128 + (status & 0x7f))
        let reason = timedOut ? "命令超时" : (state.isCancelled ? "命令已取消" : "退出码 \(exitCode)")
        let output = [reason, stdoutText.isEmpty ? nil : "标准输出：\n" + stdoutText, stderrText.isEmpty ? nil : "标准错误：\n" + stderrText].compactMap { $0 }.joined(separator: "\n\n")
        return AIChatToolResult(content: output, isError: timedOut || state.isCancelled || exitCode != 0)
    }
}

private final class ShellState: @unchecked Sendable {
    private let lock = NSLock()
    private var processID: pid_t?
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func register(_ pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        processID = pid
        if cancelled { signal(pid, SIGKILL) }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let processID { signal(processID, SIGKILL) }
    }
    func poll(_ pid: pid_t, status: inout Int32) -> pid_t {
        lock.lock(); defer { lock.unlock() }
        let result = waitpid(pid, &status, WNOHANG)
        if result == pid { processID = nil }
        return result
    }
    func finish() { lock.lock(); defer { lock.unlock() }; processID = nil }
    private func signal(_ pid: pid_t, _ value: Int32) {
        if getpgid(pid) == pid { _ = kill(-pid, value) } else { _ = kill(pid, value) }
    }
}
