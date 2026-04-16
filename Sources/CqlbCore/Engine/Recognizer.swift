import Foundation

/// Matches the raw input buffer against patterns that should bypass dictionary
/// lookup and flow through as literal ASCII (URLs, email addresses, etc.).
public final class Recognizer: @unchecked Sendable {

    public enum Pattern: Sendable {
        case url
        case email
    }

    public struct Match: Sendable {
        public let pattern: Pattern
    }

    // Compile once.
    private let urlRegex: NSRegularExpression
    private let emailRegex: NSRegularExpression
    public let isEnabled: Bool

    public init(enabled: Bool = true) {
        self.isEnabled = enabled
        // URL prefixes: http://, https://, ftp:, ftp., mailto:, file:, www.
        // Simplified from Rime's default pattern set.
        self.urlRegex = try! NSRegularExpression(
            pattern: #"^(www\.|https?:|ftp[.:]|mailto:|file:).*$"#,
            options: []
        )
        // Email: first char alpha, then alnum/./_/-/+, then @, then anything
        self.emailRegex = try! NSRegularExpression(
            pattern: #"^[A-Za-z][-_.0-9A-Za-z]*@.*$"#,
            options: []
        )
    }

    public func match(_ buffer: String) -> Match? {
        guard isEnabled, !buffer.isEmpty else { return nil }
        let range = NSRange(buffer.startIndex..<buffer.endIndex, in: buffer)
        if urlRegex.firstMatch(in: buffer, options: [], range: range) != nil {
            return Match(pattern: .url)
        }
        if emailRegex.firstMatch(in: buffer, options: [], range: range) != nil {
            return Match(pattern: .email)
        }
        return nil
    }
}
