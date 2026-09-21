/// Location of an OSC sequence in the original terminal input stream.
/// Byte offsets are independent of screen coordinates and scrollback retention.
public struct TerminalOSCSpan: Equatable, Sendable {
    /// Includes the introducer and the byte that ended OSC parsing.
    /// If that byte is ESC, a following backslash is not yet consumed by the parser.
    public let bytes: Range<UInt64>

    /// The recognized terminating byte, normally BEL, ESC, or eight-bit ST.
    public let terminator: UInt8

    /// Creates a span describing bytes consumed by a parser's OSC dispatch.
    public init(bytes: Range<UInt64>, terminator: UInt8) {
        self.bytes = bytes
        self.terminator = terminator
    }
}
