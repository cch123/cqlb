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

    /// New table containing this table's entries plus `extra` (e.g. the user
    /// dictionary). Entries already present with the same text and code are
    /// dropped. O(n + m log n): `extra` is sorted and merged into the already
    /// sorted table instead of re-sorting everything.
    public func merging(_ extra: [Entry]) -> CodeTable {
        guard !extra.isEmpty else { return self }
        func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
            if lhs.code != rhs.code { return lhs.code < rhs.code }
            return lhs.weight > rhs.weight
        }
        // Drop additions duplicating an existing (text, code) pair — the
        // main-table entry keeps its weight and position — and duplicates
        // within `extra` itself.
        var seen = Set<[String]>()
        let added = extra.filter { e in
            var i = lowerBound(e.code)
            while i < entries.count, entries[i].code == e.code {
                if entries[i].text == e.text { return false }
                i += 1
            }
            return seen.insert([e.code, e.text]).inserted
        }.sorted(by: precedes)

        var out: [Entry] = []
        out.reserveCapacity(entries.count + added.count)
        var i = 0, j = 0
        while i < entries.count || j < added.count {
            // On ties the existing entry goes first, so an added entry with
            // equal weight ranks after its main-table rivals.
            if j >= added.count || (i < entries.count && !precedes(added[j], entries[i])) {
                out.append(entries[i]); i += 1
            } else {
                out.append(added[j]); j += 1
            }
        }
        return CodeTable(name: name, presortedEntries: out)
    }

    /// Return entries whose code has `prefix` as a prefix.
    /// Results are ordered: exact match first, then shorter codes, then higher
    /// weight within the same code length.
    ///
    /// The full prefix range `[lowerBound(prefix), upperBound(prefix))` is
    /// scanned and bucketed by code length before truncating to `limit`.
    /// Truncating the lexicographic range first would be wrong: with codes
    /// sorted as `a aa aaa aaaa aaab … az`, a fixed-size lexicographic window
    /// is filled almost entirely by long `aa*` codes and drops the short
    /// `ab`…`az` codes that the ranking is supposed to put first.
    public func lookup(prefix: String, limit: Int = 64) -> [Entry] {
        guard !prefix.isEmpty, limit > 0 else { return [] }
        let lo = lowerBound(prefix)
        guard lo < entries.count else { return [] }
        let hi = prefixUpperBound(prefix, from: lo)
        guard lo < hi else { return [] }

        // Bucket entry indices by code length (UTF-8 byte count is O(1) for
        // native strings; codes are ASCII so it equals the character count).
        // Within one bucket the indices stay in table order, i.e. code asc
        // then weight desc, which serves as the deterministic tie-breaker.
        var buckets: [Int: [Int]] = [:]
        for i in lo..<hi {
            buckets[entries[i].code.utf8.count, default: []].append(i)
        }

        var results: [Entry] = []
        results.reserveCapacity(min(limit, hi - lo))
        for len in buckets.keys.sorted() {
            guard results.count < limit else { break }
            var bucket = buckets[len]!
            // Same length ⇒ the shortest bucket is exactly the exact-match
            // bucket when its length equals the prefix length; ordering by
            // length therefore already puts exact matches first.
            bucket.sort { a, b in
                let wa = entries[a].weight, wb = entries[b].weight
                return wa != wb ? wa > wb : a < b
            }
            for i in bucket {
                results.append(entries[i])
                if results.count >= limit { break }
            }
        }
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

    /// First index at or after `from` whose code does not start with `prefix`.
    /// Codes sharing a prefix form one contiguous run in the sorted table, so
    /// a binary search on the "has prefix" predicate is valid.
    private func prefixUpperBound(_ prefix: String, from: Int) -> Int {
        var lo = from
        var hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[mid].code.hasPrefix(prefix) {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

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
