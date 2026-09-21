import XCTest
import Foundation
import SwiftTerm

final class TerminalTranscriptDecoderTests: XCTestCase {
    func testEveryRowSurvivesBeyondScrollback() throws {
        var lines: [TerminalTranscriptLine] = []
        let decoder = TerminalTranscriptDecoder(columns: 80, rows: 24) { lines.append($0) }
        let expected = (1...4000).map { "row \($0)" }.joined(separator: "\r\n") + "\r\n"
        let bytes = Data(expected.utf8)
        for start in stride(from: 0, to: bytes.count, by: 113) {
            try decoder.feed(bytes.subdata(in: start..<min(start + 113, bytes.count)))
        }
        try decoder.finish()
        XCTAssertEqual(lines.map(\.text).joined(separator: "\n") + (decoder.endsWithNewline ? "\n" : ""), expected.replacingOccurrences(of: "\r\n", with: "\n"))
        XCTAssertEqual(lines.count, 4000)
    }

    func testUnicodeStylesAndCursorUpdatesRemainInProjection() throws {
        var lines: [TerminalTranscriptLine] = []
        let decoder = TerminalTranscriptDecoder(columns: 80, rows: 4) { lines.append($0) }
        let source = "busy\r\u{1b}[2K\u{1b}[38;2;255;0;0;1m界é\u{1b}[0m\r\n"
        for byte in source.utf8 { try decoder.feed(Data([byte])) }
        try decoder.finish()
        XCTAssertEqual(lines.map(\.text), ["界é"])
        XCTAssertTrue(decoder.endsWithNewline)
        let run = try XCTUnwrap(lines.first?.runs.first)
        XCTAssertEqual(run.foreground, .rgb(0xff0000))
        XCTAssertEqual(run.style & 1, 1)
    }

    func testAlternateScreenIsNotReportedAsCompleteOrdinaryText() {
        let decoder = TerminalTranscriptDecoder(columns: 80, rows: 24) { _ in }
        XCTAssertThrowsError(try decoder.feed(Data("\u{1b}[?1049h".utf8)))
    }

    func testTransientAlternateScreenCannotDisappearBetweenChunks() {
        for chunkSize in [1, 7, 4096] {
            var lines: [TerminalTranscriptLine] = []
            let decoder = TerminalTranscriptDecoder(columns: 80, rows: 24) { lines.append($0) }
            let bytes = Data("before\u{1b}[?1049hinteractive\u{1b}[?1049lafter".utf8)
            XCTAssertThrowsError(try {
                for start in stride(from: 0, to: bytes.count, by: chunkSize) {
                    try decoder.feed(bytes.subdata(in: start..<min(start + chunkSize, bytes.count)))
                }
                try decoder.finish()
            }()) { error in
                guard case TerminalTranscriptDecoder.ProjectionError.screenChanged = error else {
                    return XCTFail("Unexpected projection error: \(error)")
                }
            }
            XCTAssertThrowsError(try decoder.finish())
            XCTAssertThrowsError(try decoder.feed(Data("more".utf8)))
            XCTAssertTrue(lines.isEmpty)
        }
    }

}
