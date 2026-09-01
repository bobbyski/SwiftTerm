import Testing
@testable import SwiftTerm

/// What a full-screen program leaves behind when it exits.
///
/// TUIKit writes `ESC[?1006l ESC[?1002l ESC[?25h ESC[?1049l` on the way out:
/// stop SGR mouse reports, stop motion tracking, show the cursor, leave the
/// alternate screen. Anything still set after that is state the user's shell
/// inherits — and a terminal that keeps reporting the mouse, or keeps the
/// app's screen, is one the user has to fix by hand.
final class TUIExitTests {
    private final class Recorder: TerminalDelegate {
        var sent: [[UInt8]] = []
        func send(source: Terminal, data: ArraySlice<UInt8>) { sent.append(Array(data)) }
    }

    private func makeTerminal() -> Terminal {
        Terminal(delegate: Recorder(), options: TerminalOptions(cols: 20, rows: 5, scrollback: 10))
    }

    private static let exitSequence = "\u{1b}[?1006l\u{1b}[?1002l\u{1b}[?25h\u{1b}[?1049l"

    private func line(_ terminal: Terminal, _ row: Int) -> String {
        let buffer = terminal.buffer
        var text = ""
        for column in 0..<terminal.cols {
            // Empty cells carry code 0, not a space; rendering those as NUL
            // makes the string useless in a failure message.
            let code = buffer.lines[row + buffer.yBase][column].code
            text.append(code == 0 ? " " : (Character(UnicodeScalar(UInt32(code)) ?? " ")))
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    @Test func exitRestoresTheShellsScreen() {
        let terminal = makeTerminal()
        terminal.feed(text: "shell output")
        terminal.feed(text: "\u{1b}[?1049h")          // app starts
        terminal.feed(text: "\u{1b}[2J\u{1b}[Happlication ui")
        terminal.feed(text: Self.exitSequence)         // app exits
        #expect(line(terminal, 0) == "shell output",
                "the shell's screen must come back, not the app's")
    }

    @Test func exitStopsMouseReporting() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[?1002h\u{1b}[?1006h")
        #expect(terminal.mouseMode != .off, "the app did ask for the mouse")
        terminal.feed(text: Self.exitSequence)
        #expect(terminal.mouseMode == .off,
                "a shell that keeps reporting the mouse cannot select text")
    }

    @Test func exitShowsTheCursorAgain() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[?25l")
        terminal.feed(text: Self.exitSequence)
        #expect(terminal.cursorHidden == false, "the shell needs its cursor back")
    }

    @Test func exitLeavesWraparoundAsItFoundIt() {
        let terminal = makeTerminal()
        let before = terminal.wraparound
        terminal.feed(text: "\u{1b}[?1049h")
        terminal.feed(text: Self.exitSequence)
        #expect(terminal.wraparound == before)
    }
}
