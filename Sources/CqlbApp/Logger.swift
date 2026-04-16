import Foundation

/// File-based logger. Writes every line to /tmp/cqlb.log so we can `tail -f`
/// it during development and see every step in real time. `os.Logger` and
/// `NSLog` both get filtered or redacted by macOS in various ways; a plain
/// file skips all of that.
enum Log {
    private static let url = URL(fileURLWithPath: "/tmp/cqlb.log")
    private static let queue = DispatchQueue(label: "com.cqlb.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ category: String, _ message: String) {
        let ts = formatter.string(from: Date())
        let line = "\(ts) [\(category)] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? data.write(to: url)
                }
            }
        }
        // Also print to stderr for when cqlb is launched from a terminal.
        FileHandle.standardError.write(Data(line.utf8))
    }

    enum general {
        static func log(_ msg: String)   { Log.write("general", msg) }
        static func error(_ msg: String) { Log.write("general!", msg) }
    }
    enum engine {
        static func log(_ msg: String)   { Log.write("engine", msg) }
        static func error(_ msg: String) { Log.write("engine!", msg) }
    }
    enum tap {
        static func log(_ msg: String)   { Log.write("tap", msg) }
        static func error(_ msg: String) { Log.write("tap!", msg) }
    }
}
