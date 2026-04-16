import Foundation

public struct Entry: Sendable, Hashable {
    public let text: String
    public let code: String
    public let weight: UInt32

    public init(text: String, code: String, weight: UInt32) {
        self.text = text
        self.code = code
        self.weight = weight
    }
}

public struct Candidate: Sendable, Hashable {
    public let text: String
    public let code: String
    public let weight: UInt32
    public let source: Source

    public enum Source: UInt8, Sendable, Hashable {
        case main       // cqlb
        case pinyin     // ipinyin (i-prefix reverse lookup)
        case english    // english ('-prefix)
        case emoji      // opencc emoji
        case punct      // punctuation
    }

    public init(text: String, code: String, weight: UInt32, source: Source) {
        self.text = text
        self.code = code
        self.weight = weight
        self.source = source
    }
}
