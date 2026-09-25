/// Immutable rendition at a command boundary, separate from recorded PTY bytes.
/// Captures SGR attributes, the ANSI palette, wrapping/insertion modes, character-set mappings, tab stops, margins and the saved cursor slot.
/// The active cursor position, screen contents and other terminal modes are not captured.
public struct TerminalTranscriptRendition: Sendable {
    let attribute: Attribute
    let palette: [RGB]
    let wraparound: Bool
    let insertMode: Bool
    let reverseWraparound: Bool
    let characterSets: [[UInt8: String]?]
    let activeCharacterSet: [UInt8: String]?
    let characterSetLevel: UInt8
    let tabStops: [Bool]
    let originMode: Bool
    let marginMode: Bool
    let scrollTop: Int
    let scrollBottom: Int
    let marginLeft: Int
    let marginRight: Int
    let savedCursor: SavedCursor

    /// The parser's saved cursor slot, copied by value without screen contents.
    struct SavedCursor: Sendable {
        let x: Int
        let y: Int
        let attribute: Attribute
        let charset: [UInt8: String]?
        let originMode: Bool
        let marginMode: Bool
        let wraparound: Bool
        let reverseWraparound: Bool

        init(_ buffer: Buffer) {
            x = buffer.savedX
            y = buffer.savedY
            attribute = buffer.savedAttr
            charset = buffer.savedCharset
            originMode = buffer.savedOriginMode
            marginMode = buffer.savedMarginMode
            wraparound = buffer.savedWraparound
            reverseWraparound = buffer.savedReverseWraparound
        }

        func restore(to buffer: Buffer) {
            buffer.savedX = max(0, min(x, buffer.cols - 1))
            buffer.savedY = max(0, min(y, buffer.rows - 1))
            buffer.savedAttr = attribute
            buffer.savedCharset = charset
            buffer.savedOriginMode = originMode
            buffer.savedMarginMode = marginMode
            buffer.savedWraparound = wraparound
            buffer.savedReverseWraparound = reverseWraparound
        }
    }

    /// Value storage prevents the decoder sharing mutable terminal colors.
    struct RGB: Sendable {
        let red: UInt16
        let green: UInt16
        let blue: UInt16
        init(_ color: Color) {
            red = color.red; green = color.green; blue = color.blue
        }
        var color: Color { Color(red: red, green: green, blue: blue) }
    }
}
