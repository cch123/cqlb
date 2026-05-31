import Darwin
import Foundation

/// File-based logger. Writes every line to /tmp/cqlb-ime.log so we can
/// `tail -f` it during development. IMK debugging is especially painful
/// because `TextInputMenuAgent` relaunches us on every code change, so
/// stderr is often not captured anywhere visible.
enum Log {
    private static let url = URL(fileURLWithPath: "/tmp/cqlb-ime.log")
    private static let queue = DispatchQueue(label: "com.cqlb.ime.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    private static let shouldMirrorToStderr = isatty(STDERR_FILENO) == 1

    static func write(_ category: String, _ message: String) {
        let ts = formatter.string(from: Date())
        let line = "\(ts) [\(category)] \(message)\n"
        queue.sync {
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? data.write(to: url)
                }
                // LaunchServices/IMK often start input methods without a
                // usable stderr. File logging is the source of truth; stderr
                // mirroring is only for interactive terminal runs.
                if shouldMirrorToStderr {
                    try? FileHandle.standardError.write(contentsOf: data)
                }
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
