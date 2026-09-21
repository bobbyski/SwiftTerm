import XCTest
import Foundation
@testable import SwiftTerm

final class TerminalTextCaptureTests: XCTestCase {
    private final class Sink: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    func testSnapshotExcludesEarlierEcho() throws {
        let sink = Sink()
        let terminal = Terminal(delegate: sink)
        terminal.feed(text: "prompt> echo value\r\n")
        let mark = terminal.markTextPosition()
        terminal.feed(text: "héllo\r\n")
        XCTAssertEqual(try terminal.text(since: mark).trimmingCharacters(in: .whitespacesAndNewlines), "héllo")
    }

    func testAlternateScreenCannotMasqueradeAsCommandText() {
        let sink = Sink()
        let terminal = Terminal(delegate: sink)
        let mark = terminal.markTextPosition()
        terminal.feed(text: "\u{1b}[?1049h")
        XCTAssertThrowsError(try terminal.text(since: mark))
    }

    func testEvictedHistoryIsReported() {
        let sink = Sink()
        let terminal = Terminal(delegate: sink)
        let mark = terminal.markTextPosition()
        terminal.feed(text: String(repeating: "line\r\n", count: 3000))
        XCTAssertThrowsError(try terminal.text(since: mark))
    }
}
