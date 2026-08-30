import Testing
@testable import SwiftTerm

/// What the terminal answers when a program asks where the cursor is.
///
/// The interesting case is the **pending wrap**. Writing into the last column
/// leaves the cursor there with a flag saying "wrap before the next glyph";
/// `buffer.x` holds `cols` to carry that flag. It is an internal state, and a
/// program asking for the cursor position must never be told the cursor is in
/// a column that does not exist — a full-screen program uses the answer to
/// lay itself out, and one column past the edge is a layout it cannot draw.
///
/// xterm reports the last column in this state, which is where the cursor
/// visibly is.
final class CursorPositionReportTests {
    private final class Recorder: TerminalDelegate {
        var sent: [[UInt8]] = []
        func send(source: Terminal, data: ArraySlice<UInt8>) { sent.append(Array(data)) }

        /// The text of every reply, joined.
        var text: String { sent.map { String(decoding: $0, as: UTF8.self) }.joined() }
    }

    private func makeTerminal(cols: Int = 20, rows: Int = 5) -> (Terminal, Recorder) {
        let recorder = Recorder()
        let terminal = Terminal(
            delegate: recorder,
            options: TerminalOptions(cols: cols, rows: rows, scrollback: 0)
        )
        return (terminal, recorder)
    }

    /// The column from a `CSI row ; col R` reply.
    private func reportedColumn(_ text: String) -> Int? {
        guard let range = text.range(of: "R", options: .backwards) else { return nil }
        let body = text[text.startIndex..<range.lowerBound]
        guard let semicolon = body.lastIndex(of: ";") else { return nil }
        return Int(body[body.index(after: semicolon)...])
    }

    @Test func cursorReportStaysInsideTheGridAfterFillingARow() {
        let (terminal, recorder) = makeTerminal(cols: 20)
        // Exactly one row's worth: the cursor ends in the last column with a
        // wrap pending, which is the state a full-width TUI border leaves.
        terminal.feed(text: String(repeating: "x", count: 20))
        terminal.feed(text: "\u{1b}[6n")

        let column = reportedColumn(recorder.text)
        #expect(column != nil, "no cursor report came back")
        #expect(column! <= 20,
                "reported column \(column ?? -1) is past the right edge of a 20-column grid")
        #expect(column == 20, "xterm reports the last column while a wrap is pending")
    }

    @Test func cursorReportIsNormalAwayFromTheEdge() {
        let (terminal, recorder) = makeTerminal(cols: 20)
        terminal.feed(text: String(repeating: "x", count: 5))
        terminal.feed(text: "\u{1b}[6n")
        #expect(reportedColumn(recorder.text) == 6, "1-based, so five glyphs put the cursor at 6")
    }

    @Test func cursorReportStaysInsideTheGridForTheDECVariant() {
        let (terminal, recorder) = makeTerminal(cols: 20)
        terminal.feed(text: String(repeating: "x", count: 20))
        // The `?` form, which xterm answers for the same question.
        terminal.feed(text: "\u{1b}[?6n")
        let column = reportedColumn(recorder.text.replacingOccurrences(of: ";1R", with: "R"))
        #expect(column != nil)
        #expect(column! <= 20, "the DEC form must clamp too")
    }

    @Test func writingPastTheEdgeWrapsRatherThanReportingOffGrid() {
        let (terminal, recorder) = makeTerminal(cols: 20)
        terminal.feed(text: String(repeating: "x", count: 21))
        terminal.feed(text: "\u{1b}[6n")
        // The 21st glyph is what actually performs the deferred wrap.
        #expect(reportedColumn(recorder.text) == 2, "one glyph onto the next row")
    }
}
