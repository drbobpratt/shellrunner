import Foundation
import Observation
import SwiftData

/// Keeps one `ProcessRunner` per saved command so output and running state
/// survive switching between commands in the sidebar (and a running command
/// is never orphaned when its detail view goes away).
final class RunnerStore {
    static let shared = RunnerStore()
    private var runners: [PersistentIdentifier: ProcessRunner] = [:]
    private init() {}

    func runner(for command: SavedCommand) -> ProcessRunner {
        let key = command.persistentModelID
        if let existing = runners[key] { return existing }
        let runner = ProcessRunner()
        runners[key] = runner
        return runner
    }

    func forget(_ command: SavedCommand) {
        let key = command.persistentModelID
        runners[key]?.cancel()
        runners[key] = nil
    }
}

/// Runs a shell command via the user's login shell so aliases, functions, and PATH
/// customizations from .zshrc are honored, and streams stdout/stderr live.
@Observable
final class ProcessRunner {
    private(set) var output: String = ""
    private(set) var isRunning: Bool = false
    private(set) var exitCode: Int32?

    /// Called on the main actor with the full output once the process finishes
    /// (success, failure, or failure to launch).
    var onFinish: ((Int32, String) -> Void)?

    /// The shell to invoke commands through. zsh is macOS's default since Catalina.
    var shellPath: String = "/bin/zsh"

    /// Output beyond this many UTF-8 bytes is trimmed from the front.
    static let maxOutputBytes = 1_000_000

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var inputPipe: Pipe?

    // Reader state, touched from background threads; guarded by `lock`.
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var undecoded = Data()
    @ObservationIgnored private var pendingText = ""

    func run(command: String, workingDirectory: String? = nil, extraEnv: [String: String] = [:]) {
        guard !isRunning else { return }

        output = ""
        exitCode = nil
        lock.withLock {
            undecoded.removeAll()
            pendingText = ""
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        // -i makes zsh source .zshrc (aliases, PATH tweaks, nvm/pyenv shims, etc.)
        // -l makes zsh also source .zprofile/.zlogin as a login shell would.
        process.arguments = ["-i", "-l", "-c", command]

        if let workingDirectory, !workingDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        if !extraEnv.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in extraEnv { env[key] = value }
            process.environment = env
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let reader = pipe.fileHandleForReading

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        self.inputPipe = stdinPipe

        reader.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {            // EOF: stop being called
                handle.readabilityHandler = nil
                return
            }
            self?.ingest(data)
        }

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            reader.readabilityHandler = nil
            // Pull out anything still sitting in the pipe so the tail of the
            // output isn't lost, without blocking if a background child still
            // holds the write end open.
            self.drain(reader)
            self.ingest(Data(), flush: true)
            let status = proc.terminationStatus
            Task { @MainActor [weak self] in self?.finish(status: status) }
        }

        self.process = process
        isRunning = true

        do {
            try process.run()
        } catch {
            reader.readabilityHandler = nil
            self.process = nil
            self.inputPipe = nil
            isRunning = false
            output += "[Failed to launch process: \(error.localizedDescription)]\n"
            exitCode = -1
            onFinish?(-1, output)
        }
    }

    /// Sends a line of text to the running process's stdin, as if the user typed
    /// it and pressed Return. No-op if nothing is running.
    func sendInput(_ text: String) {
        guard isRunning, let inputPipe else { return }
        let line = text.hasSuffix("\n") ? text : text + "\n"
        guard let data = line.data(using: .utf8) else { return }
        try? inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    /// Stops the command *and* everything it spawned. Sends SIGTERM to the whole
    /// process tree, then SIGKILL after 2s if the shell is still alive (interactive
    /// shells can shrug off SIGTERM).
    func cancel() {
        guard let process, process.isRunning else { return }
        let pid = process.processIdentifier
        DispatchQueue.global().async {
            for child in Self.descendants(of: pid).reversed() { kill(child, SIGTERM) }
            kill(pid, SIGTERM)

            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                guard process.isRunning else { return }
                for child in Self.descendants(of: pid).reversed() { kill(child, SIGKILL) }
                kill(pid, SIGKILL)
            }
        }
    }

    // MARK: - Internals

    /// Appends bytes, decodes as much valid UTF-8 as possible (holding back an
    /// incomplete multi-byte sequence for the next chunk), and queues a UI flush.
    private func ingest(_ data: Data, flush: Bool = false) {
        let hasNewText: Bool = lock.withLock {
            undecoded.append(data)
            let text = Self.decodeUTF8(&undecoded, flush: flush)
            pendingText += text
            return !text.isEmpty
        }
        if hasNewText {
            Task { @MainActor [weak self] in self?.flushPending() }
        }
    }

    private func drain(_ handle: FileHandle) {
        let fd = handle.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            ingest(Data(buffer[0..<n]))
        }
    }

    @MainActor
    private func flushPending() {
        let text: String = lock.withLock {
            let t = pendingText
            pendingText = ""
            return t
        }
        guard !text.isEmpty else { return }
        output += text
        if output.utf8.count > Self.maxOutputBytes {
            output = "[… earlier output truncated …]\n" + String(output.suffix(Self.maxOutputBytes / 4))
        }
    }

    @MainActor
    private func finish(status: Int32) {
        flushPending()
        isRunning = false
        exitCode = status
        process = nil
        inputPipe = nil
        onFinish?(status, output)
    }

    private static func decodeUTF8(_ buffer: inout Data, flush: Bool) -> String {
        if flush || buffer.isEmpty {
            let s = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll()
            return s
        }
        // A UTF-8 scalar is at most 4 bytes, so at most 3 trailing bytes can be an
        // incomplete sequence. Find the longest prefix that decodes cleanly.
        for held in 0...min(3, buffer.count) {
            let end = buffer.count - held
            if let s = String(data: buffer.prefix(end), encoding: .utf8) {
                buffer = Data(buffer.suffix(held))
                return s
            }
        }
        // Genuinely invalid bytes: decode lossily rather than dropping them.
        let s = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        return s
    }

    /// All descendant PIDs of `pid` (children, grandchildren, …).
    private static func descendants(of pid: pid_t) -> [pid_t] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-P", "\(pid)"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let kids = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0) }
        return kids + kids.flatMap { descendants(of: $0) }
    }
}
