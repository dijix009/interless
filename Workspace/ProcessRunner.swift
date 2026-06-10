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
        /// True when stdout or stderr exceeded `maxOutputBytes` and was truncated.
        public let truncated: Bool
    }

    public init() {}

    /// - Parameter maxOutputBytes: per-stream cap on captured output read back into
    ///   memory. Bounds peak RAM for verbose commands (large `git diff`, test logs);
    ///   the default is generous so normal output is never truncated.
    public func run(
        executableURL: URL,
        arguments: [String],
        timeout: Duration,
        maxOutputBytes: Int = 8 * 1024 * 1024
    ) async throws -> Result {
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

        defer { control.cancelWatchdog() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in
                    control.cancelWatchdog()
                    continuation.resume()
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                // Timeout watchdog: terminate if still running when it fires. Held on
                // `control` so it is cancelled the instant the process exits, instead
                // of sleeping out the whole timeout (which leaked a Task per fast call).
                control.setWatchdog(Task {
                    try? await Task.sleep(for: timeout)
                    if control.process.isRunning {
                        control.markTimedOut()
                        control.process.terminate()
                    }
                })
            }
        } onCancel: {
            control.process.terminate()
        }

        try? outHandle.close()
        try? errHandle.close()
        let (out, outTruncated) = Self.readBounded(outURL, maxBytes: maxOutputBytes)
        let (err, errTruncated) = Self.readBounded(errURL, maxBytes: maxOutputBytes)
        return Result(
            stdout: out,
            stderr: err,
            exitCode: process.terminationStatus,
            timedOut: control.timedOut,
            truncated: outTruncated || errTruncated)
    }

    /// Reads at most `maxBytes` from `url`; the Bool is true if the file held more
    /// (i.e. output was truncated). Avoids slurping an unbounded subprocess capture.
    private static func readBounded(_ url: URL, maxBytes: Int) -> (Data, Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (Data(), false) }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: max(0, maxBytes))) ?? Data()
        let hasMore = ((try? handle.read(upToCount: 1))?.isEmpty == false)
        return (data, hasMore)
    }
}

/// Holds the `Process` for use from the `@Sendable` cancel/timeout closures. Safe
/// because `Process` here is only started/terminated (thread-safe) and the flag is
/// lock-guarded.
private final class ProcessControl: @unchecked Sendable {
    let process: Process
    private let lock = NSLock()
    private var _timedOut = false
    private var _watchdog: Task<Void, Never>?

    init(_ process: Process) { self.process = process }

    var timedOut: Bool { lock.withLock { _timedOut } }
    func markTimedOut() { lock.withLock { _timedOut = true } }
    func setWatchdog(_ task: Task<Void, Never>) { lock.withLock { _watchdog = task } }
    func cancelWatchdog() { lock.withLock { _watchdog?.cancel(); _watchdog = nil } }
}
