import XCTest
import Foundation
@testable import SwiftTerm

final class TerminalInputObservationTests: XCTestCase {
    private final class Sink: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    func testFragmentedInputRetainsExactOffsetsAndUnicodeBytes() throws {
        let sink = Sink()
        let terminal = Terminal(delegate: sink)
        let prefix = "prompt> héllo\r\n"
        let start = "\u{1b}]133;C;example\u{7}"
        let output = "\u{1b}[31mresult é\u{1b}[0m\r\n"
        let end = "\u{1b}]133;D;0\u{7}"
        let wire = Array((prefix + start + output + end + "prompt> ").utf8)
        var recorded: [UInt8] = []
        var spans: [TerminalOSCSpan] = []
        terminal.parser.inputObserver = { offset, bytes in
            XCTAssertEqual(offset, UInt64(recorded.count))
            recorded.append(contentsOf: bytes)
        }
        terminal.registerOscHandler(code: 133) { _ in
            if let span = terminal.parser.currentOSCSpan { spans.append(span) }
        }
        // Nonzero slice indices and a marker split at every byte boundary.
        for byte in wire {
            terminal.feed(buffer: [0, byte, 0][1..<2])
        }
        XCTAssertEqual(recorded, wire)
        XCTAssertEqual(spans.count, 2)
        let first = try XCTUnwrap(spans.first)
        let last = try XCTUnwrap(spans.last)
        XCTAssertEqual(first.bytes.lowerBound, UInt64(prefix.utf8.count))
        XCTAssertEqual(first.terminator, 7)
        let captured = recorded[Int(first.bytes.upperBound)..<Int(last.bytes.lowerBound)]
        XCTAssertEqual(String(decoding: captured, as: UTF8.self), output)
        XCTAssertNil(terminal.parser.currentOSCSpan)
    }

    func testEscapeTerminatorReportsOnlyConsumedPrefix() throws {
        let sink = Sink()
        let terminal = Terminal(delegate: sink)
        var span: TerminalOSCSpan?
        terminal.registerOscHandler(code: 133) { _ in span = terminal.parser.currentOSCSpan }
        terminal.feed(text: "abc\u{1b}]133;A\u{1b}")
        let value = try XCTUnwrap(span)
        XCTAssertEqual(value.bytes, 3..<11)
        XCTAssertEqual(value.terminator, 27)
        terminal.feed(text: "\\tail")
        XCTAssertNil(terminal.parser.currentOSCSpan)
    }

    func testRecordingSurvivesScrollbackEvictionAndScreenReset() {
        let sink = Sink()
        let terminal = Terminal(delegate: sink)
        var total: UInt64 = 0
        terminal.parser.inputObserver = { offset, bytes in
            XCTAssertEqual(offset, total)
            total += UInt64(bytes.count)
        }
        let chunk = String(repeating: "line\r\n", count: 4000)
        terminal.feed(text: chunk)
        terminal.feed(text: "\u{1b}c")
        terminal.feed(text: "after reset")
        XCTAssertEqual(total, UInt64(chunk.utf8.count + 2 + 11))
    }
}
