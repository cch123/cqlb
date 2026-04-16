import Foundation
import CqlbCore

// Minimal CLI for verifying dict loading and query behavior.
//
// Usage:
//   cqlb-query <dict-path> <query> [more queries...]
//   cqlb-query ~/Library/Rime/cqlb.dict.yaml aa
//
// Prints the top N candidates for each query along with load timing.

func usage() -> Never {
    let name = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "cqlb-query"
    FileHandle.standardError.write(Data("""
    usage: \(name) <dict-path> <query> [query...]
      --max N        cap results per query (default 20)
      --min-weight W drop entries with weight < W while loading (default 0)
    """.utf8))
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
var limit = 20
var minWeight: UInt32 = 0
var useCache = true
var cacheDir: String = ("~/Library/Caches/cqlb" as NSString).expandingTildeInPath

// Simple flag parsing.
var i = 0
while i < args.count {
    switch args[i] {
    case "--max":
        guard i + 1 < args.count, let n = Int(args[i + 1]) else { usage() }
        limit = n
        args.removeSubrange(i..<i + 2)
    case "--min-weight":
        guard i + 1 < args.count, let n = UInt32(args[i + 1]) else { usage() }
        minWeight = n
        args.removeSubrange(i..<i + 2)
    case "--no-cache":
        useCache = false
        args.remove(at: i)
    case "--cache-dir":
        guard i + 1 < args.count else { usage() }
        cacheDir = (args[i + 1] as NSString).expandingTildeInPath
        args.removeSubrange(i..<i + 2)
    default:
        i += 1
    }
}

guard args.count >= 2 else { usage() }
let dictPath = args[0]
let queries = Array(args.dropFirst())

let url = URL(fileURLWithPath: (dictPath as NSString).expandingTildeInPath)
let cacheURL = URL(fileURLWithPath: cacheDir)
    .appendingPathComponent(url.lastPathComponent + ".bin")

let loadStart = Date()
let table: CodeTable
var fromCache = false
do {
    if useCache {
        let result = try DictLoader.loadCached(
            source: url,
            cache: cacheURL,
            options: DictLoadOptions(maxEntries: nil, minWeight: minWeight, skipStemColumn: true)
        )
        table = result.table
        fromCache = result.fromCache
    } else {
        table = try DictLoader.load(
            from: url,
            options: DictLoadOptions(maxEntries: nil, minWeight: minWeight, skipStemColumn: true)
        )
    }
} catch {
    FileHandle.standardError.write(Data("load failed: \(error)\n".utf8))
    exit(1)
}
let loadMs = Date().timeIntervalSince(loadStart) * 1000
let origin = fromCache ? "cache" : "yaml"
print("loaded \(table.count) entries from \(table.name) [\(origin)] in \(String(format: "%.1f", loadMs)) ms")

for q in queries {
    let start = Date()
    let results = table.lookup(prefix: q, limit: limit)
    let elapsedUs = Date().timeIntervalSince(start) * 1_000_000
    print("\nquery \"\(q)\" → \(results.count) results (\(String(format: "%.0f", elapsedUs)) μs)")
    for (rank, e) in results.enumerated() {
        print(String(format: "  %2d. %-12@ [%@] w=%u", rank + 1, e.text as NSString, e.code, e.weight))
    }
}
