import Darwin
import Foundation

/// File-based logger. Writes every line to /tmp/cqlb-ime.log so we can
/// `tail -f` it during development. IMK debugging is especially painful
/// because `TextInputMenuAgent` relaunches us on every code change, so
/// stderr is often not captured anywhere visible.
enum Log {
    private static let url = URL(fileURLWithPath: "/tmp/cqlb-ime.log")
    private static let queue = DispatchQueue(label: "com.cqlb.ime.log", qos: .utility)
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    private static let shouldMirrorToStderr = isatty(STDERR_FILENO) == 1
    /// The log is truncated when it exceeds this size at process start, so
    /// it cannot grow without bound across a long login session.
    private static let maxBytes: UInt64 = 1 << 20

    /// Opened once, on the log queue. The previous implementation did
    /// open + seek + write + close synchronously on the calling (main)
    /// thread for every line.
    private static let handle: FileHandle? = {
        let fm = FileManager.default
        let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
        if size > maxBytes || !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: url)
        _ = try? h?.seekToEnd()
        return h
    }()

    static func write(_ category: String, _ message: String) {
        let now = Date()
        queue.async {
            let line = "\(formatter.string(from: now)) [\(category)] \(message)\n"
            let data = Data(line.utf8)
            try? handle?.write(contentsOf: data)
            // LaunchServices/IMK often start input methods without a
            // usable stderr. File logging is the source of truth; stderr
            // mirroring is only for interactive terminal runs.
            if shouldMirrorToStderr {
                try? FileHandle.standardError.write(contentsOf: data)
            }
        }
    }

    enum general {
        static func log(_ msg: String)   { Log.write("general", msg) }
        static func error(_ msg: String) { Log.write("general!", msg) }
    }
    enum engine {
        static func log(_ msg: String)   { Log.write("engine", msg) }
        static func error(_ msg: String) { Log.write("engine!", msg) }
    }
    enum imk {
        static func log(_ msg: String)   { Log.write("imk", msg) }
        static func error(_ msg: String) { Log.write("imk!", msg) }
    }
}
