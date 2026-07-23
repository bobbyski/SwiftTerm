import Foundation

/// A contiguous range of terminal cells occupied by a detected link.
public struct TerminalLinkRange: Equatable {
    /// Absolute row in the terminal's display buffer.
    public let row: Int

    /// Half-open column range occupied by the link on ``row``.
    public let columns: Range<Int>

    /// Create a terminal link range.
    public init(row: Int, columns: Range<Int>) {
        self.row = row
        self.columns = columns
    }
}

/// A hyperlink resolved from terminal content.
public struct TerminalLink: Equatable {
    /// How the link entered the terminal buffer.
    public enum Kind: Equatable {
        /// An OSC 8 hyperlink explicitly supplied by the terminal application.
        case explicit

        /// A URL or path recognized from ordinary terminal text.
        case implicit
    }

    /// Destination supplied by OSC 8 or recognized from displayed text.
    public let target: String

    /// Text visible in the terminal for the matched link.
    public let displayedText: String

    /// Whether the link was explicit or implicitly detected.
    public let kind: Kind

    /// OSC 8 metadata. Implicit links use an empty dictionary.
    public let parameters: [String: String]

    /// Cell ranges occupied by the link, including wrapped rows.
    public let ranges: [TerminalLinkRange]

    /// Create a typed terminal link result.
    public init(
        target: String,
        displayedText: String,
        kind: Kind,
        parameters: [String: String] = [:],
        ranges: [TerminalLinkRange]
    ) {
        self.target = target
        self.displayedText = displayedText
        self.kind = kind
        self.parameters = parameters
        self.ranges = ranges
    }
}
