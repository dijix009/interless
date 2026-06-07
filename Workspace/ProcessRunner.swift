import Foundation

/// Runs a subprocess to completion with timeout + cooperative cancellation,
/// capturing stdout/stderr (ARCHITECTURE.md §14; reusable for Phase 3 §10 tooling).
///
/// Output is redirected to temp files rather than pipes, which sidesteps the
/// classic OS pipe-buffer (~64 KiB) deadlock entirely — `git status` on a large
/// repo cannot block us, and there is no concurrent-drain `Sendable` juggling.
public struct ProcessRunner: Sendable {

    public struct Result: Sendable {
        public let stdout: Data
        public let stderr: Data
        public let exitCode: Int32
        public let timedOut: Bool
    }

    public init() {}

    public func run(executableURL: URL, arguments: [String], timeout: Duration) async throws -> Result {
        let fm = FileManager.default
        let outURL = fm.temporaryDirectory.appendingPathComponent("if-\(UUID().uuidString).out")
        let errURL = fm.temporaryDirectory.appendingPathComponent("if-\(UUID().uuidString).err")
        fm.createFile(atPath: outURL.path, contents: nil)
        fm.createFile(atPath: errURL.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)
        defer {
            try? fm.removeItem(at: outURL)
            try? fm.removeItem(at: errURL)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outHandle
        process.standardError = errHandle
        let control = ProcessControl(process)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                // Timeout watchdog: terminate if still running when it fires.
                Task {
                    try? await Task.sleep(for: timeout)
                    if control.process.isRunning {
                        control.markTimedOut()
                        control.process.terminate()
                    }
                }
            }
        } onCancel: {
            control.process.terminate()
        }

        try? outHandle.close()
        try? errHandle.close()
        let out = (try? Data(contentsOf: outURL)) ?? Data()
        let err = (try? Data(contentsOf: errURL)) ?? Data()
        return Result(stdout: out, stderr: err, exitCode: process.terminationStatus, timedOut: control.timedOut)
    }
}

/// Holds the `Process` for use from the `@Sendable` cancel/timeout closures. Safe
/// because `Process` here is only started/terminated (thread-safe) and the flag is
/// lock-guarded.
private final class ProcessControl: @unchecked Sendable {
    let process: Process
    private let lock = NSLock()
    private var _timedOut = false

    init(_ process: Process) { self.process = process }

    var timedOut: Bool { lock.withLock { _timedOut } }
    func markTimedOut() { lock.withLock { _timedOut = true } }
}
