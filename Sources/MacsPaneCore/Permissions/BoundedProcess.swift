import Foundation

/// A value written by a `FileHandle` readability handler (its own queue) and read by the waiting
/// thread. Small and local on purpose — the alternative is an unsynchronised `var` captured by an
/// escaping closure, which is a data race whether or not it has bitten yet.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}

/// Run a command line tool and get its output back, **never waiting longer than you said**.
///
/// Every shell-out in the app goes through here, because the obvious way to write one has three
/// failure modes that all end the same way — the calling thread never comes back:
///
/// 1. `readDataToEndOfFile()` returns at EOF, not at exit. A child that holds stdout open blocks the
///    reader indefinitely, and nothing guarantees EOF ever arrives.
/// 2. A deadline that sends SIGTERM and stops there waits forever on a child that ignores it.
///    (Verified: a child running `trap '' TERM; sleep 30` hung the old reader past 8 s with a 0.3 s
///    deadline; through this runner the same child returns in `timeout + reapGrace`.)
/// 3. `Process.terminate()` called from a timer thread while another sits in `waitUntilExit()`.
///    `Process` is not thread-safe, and `isRunning`/`terminate()` race — the child can be reaped
///    between the two, and terminating an already-reaped task raises an ObjC exception, which Swift
///    cannot catch and which takes the app down.
///
/// Where that matters most: the callers run on **serial** queues (the System page samples on one,
/// once per tick). One unbounded wait there wedges the queue for the rest of the session, and every
/// later tick queues up behind it — the page's figures stop and never resume, with no crash and
/// nothing in the log to say why.
///
/// So: the pipe drains asynchronously, every wait has a deadline, and the escalation is a direct
/// `kill(2)` rather than mutating `Process` from another thread.
public enum BoundedProcess {
    /// How long to wait past the kill before giving up on the child and returning anyway. Something
    /// that survives SIGKILL is stuck in the kernel; nothing here will free it, and blocking the
    /// caller on it is the one outcome that must not happen.
    public static let reapGrace: TimeInterval = 0.5

    public struct Outcome: Sendable {
        /// What the child wrote to stdout before it finished (or was killed).
        public let output: Data
        /// True when the child had to be killed. Callers should treat the output as unusable: a
        /// half-written reading is worse than no reading, because it reads as a real drop to zero.
        public let timedOut: Bool
    }

    /// Runs `executable`, returning at the latest after `timeout + reapGrace`.
    /// A tool that cannot be launched comes back as a timed-out `Outcome` with no output.
    public static func run(_ executable: String,
                           _ arguments: [String],
                           timeout: TimeInterval,
                           captureOutput: Bool = true) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice

        let buffer = Locked(Data())
        let drained = DispatchSemaphore(value: 0)
        let readHandle = attachStdout(to: process, capture: captureOutput, into: buffer, drained: drained)

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            readHandle?.readabilityHandler = nil
            return Outcome(output: Data(), timedOut: true)
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            // Straight to SIGKILL: these are read-only tools with nothing to clean up, and a
            // catchable signal is exactly what a wedged child would ignore.
            let pid = process.processIdentifier
            if pid > 0 { kill(pid, SIGKILL) }
            _ = exited.wait(timeout: .now() + reapGrace)
        }
        // The child is gone (or unreachable); its EOF should be a moment behind. Bounded either way.
        _ = drained.wait(timeout: .now() + reapGrace)
        readHandle?.readabilityHandler = nil
        try? readHandle?.close()

        return Outcome(output: buffer.value, timedOut: timedOut)
    }

    /// Drains stdout as it arrives rather than after the child exits — a child writing more than a
    /// pipe buffer (64 KB) blocks until someone reads, so a reader that waits for exit first
    /// deadlocks against it. Signals `drained` at EOF; signals immediately when not capturing.
    private static func attachStdout(to process: Process,
                                     capture: Bool,
                                     into buffer: Locked<Data>,
                                     drained: DispatchSemaphore) -> FileHandle? {
        guard capture else {
            process.standardOutput = FileHandle.nullDevice
            drained.signal()
            return nil
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil   // EOF: the child closed stdout
                drained.signal()
                return
            }
            buffer.mutate { $0.append(chunk) }
        }
        return handle
    }
}
