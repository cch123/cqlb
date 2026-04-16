import Foundation

public final class CodeTable: @unchecked Sendable {
    public let name: String
    private let entries: [Entry]  // sorted by code ascending, stable within same code by weight desc

    public init(name: String, entries: [Entry]) {
        self.name = name
        self.entries = entries.sorted { lhs, rhs in
            if lhs.code != rhs.code { return lhs.code < rhs.code }
            return lhs.weight > rhs.weight
        }
    }

    /// Used by `BinaryCache.read` to skip re-sorting entries that were
    /// persisted in final sorted order.
    public init(name: String, presortedEntries: [Entry]) {
        self.name = name
        self.entries = presortedEntries
    }

    public var count: Int { entries.count }

    /// Return entries whose code has `prefix` as a prefix.
    /// Results are ordered: shorter codes first, then higher weight within the same code length.
    public func lookup(prefix: String, limit: Int = 64) -> [Entry] {
        guard !prefix.isEmpty else { return [] }
        let lowerIdx = lowerBound(prefix)
        guard lowerIdx < entries.count else { return [] }

        var results: [Entry] = []
        results.reserveCapacity(min(limit * 2, 128))
        var i = lowerIdx
        while i < entries.count {
            let e = entries[i]
            if !e.code.hasPrefix(prefix) { break }
            results.append(e)
            i += 1
            if results.count >= limit * 4 { break }  // grab extra then rerank
        }

        // Rank: exact matches first, then shortest code, then weight desc.
        // Use utf8.count (O(1) for native strings) instead of Character-level
        // count (O(n)). Entry codes are ASCII pinyin-like tokens so the two
        // values are identical. Pre-decorating avoids repeated per-compare
        // recomputation in the sort's O(k log k) passes.
        let prefixUtf8Count = prefix.utf8.count
        var decorated = results.map { entry -> (entry: Entry, isExact: Bool, len: Int) in
            let len = entry.code.utf8.count
            return (entry, len == prefixUtf8Count && entry.code == prefix, len)
        }
        decorated.sort { lhs, rhs in
            if lhs.isExact != rhs.isExact { return lhs.isExact }
            if lhs.len != rhs.len { return lhs.len < rhs.len }
            return lhs.entry.weight > rhs.entry.weight
        }
        results = decorated.map(\.entry)
        if results.count > limit { results.removeLast(results.count - limit) }
        return results
    }

    /// Exact match on code. Returns all entries with exactly that code, ordered by weight desc.
    public func exactMatch(code: String) -> [Entry] {
        let lowerIdx = lowerBound(code)
        var results: [Entry] = []
        var i = lowerIdx
        while i < entries.count && entries[i].code == code {
            results.append(entries[i])
            i += 1
        }
        return results
    }

    // MARK: - Binary search

    /// Smallest index `i` such that `entries[i].code >= target`.
    private func lowerBound(_ target: String) -> Int {
        var lo = 0
        var hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[mid].code < target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    public func allEntries() -> [Entry] { entries }
}
