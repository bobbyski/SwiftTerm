/// A terminal default remains symbolic so the renderer resolves its channel correctly.
public enum TerminalTranscriptColor: Codable, Equatable, Sendable {
    /// Default foreground or background, according to the run's channel.
    case defaultColor
    /// Inverted default for that channel.
    case defaultInvertedColor
    /// An explicit packed 24-bit RGB color.
    case rgb(UInt32)
}

/// A serializable text projection of one terminal row.
public struct TerminalTranscriptLine: Codable, Equatable, Sendable {
    /// True when this physical row continues the previous logical line.
    public let isWrapped: Bool
    /// Adjacent text with identical terminal styling is stored as one run.
    public let runs: [TerminalTranscriptRun]
    /// The row's text without styling.
    public var text: String { runs.map(\.text).joined() }

    /// Creates a decoded row or a styled text window for transcript rendering.
    public init(isWrapped: Bool, runs: [TerminalTranscriptRun]) {
        self.isWrapped = isWrapped
        self.runs = runs
    }
}

/// One styled run, with colors resolved when the row was captured.
public struct TerminalTranscriptRun: Codable, Equatable, Sendable {
    /// Visible characters; wide glyphs occur only once.
    public var text: String
    /// Foreground color, retaining symbolic terminal defaults.
    public let foreground: TerminalTranscriptColor
    /// Background color, retaining symbolic terminal defaults.
    public let background: TerminalTranscriptColor
    /// Terminal CharacterStyle flags.
    public let style: UInt8
    /// Terminal UnderlineStyle raw value.
    public let underline: UInt8

    /// Explicit underline ink; nil follows the text foreground.
    public let underlineColor: TerminalTranscriptColor?

    /// Creates styled transcript text with symbolic defaults or explicit colors.
    public init(text: String, foreground: TerminalTranscriptColor = .defaultColor,
                background: TerminalTranscriptColor = .defaultColor,
                style: UInt8 = 0, underline: UInt8 = 0, underlineColor: TerminalTranscriptColor? = nil) {
        self.text = text
        self.foreground = foreground
        self.background = background
        self.style = style
        self.underline = underline
        self.underlineColor = underlineColor
    }
}
