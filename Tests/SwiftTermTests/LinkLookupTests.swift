//
//  LinkLookupTests.swift
//
//
//  Created by Codex on 1/31/26.
//

import Foundation
import Testing

@testable import SwiftTerm

final class LinkLookupTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {
    }

    private func write(_ text: String, terminal: Terminal, row: Int, col: Int = 0) {
        guard row >= 0 && row < terminal.displayBuffer.lines.count else {
            return
        }
        let line = terminal.displayBuffer.lines[row]
        var x = col
        for ch in text {
            guard x < terminal.cols else { break }
            line[x] = terminal.makeCharData(attribute: CharData.defaultAttr, char: ch)
            x += 1
        }
    }

    @Test func testExplicitLinkLookup() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 10, rows: 1))
        terminal.feed(text: "abc")

        let payload = "id;https://example.com"
        let atom = TinyAtom.lookup(value: payload)!
        let line = terminal.displayBuffer.lines[0]
        var cd = line[1]
        cd.setPayload(atom: atom)
        line[1] = cd

        let link = terminal.link(at: .buffer(Position(col: 1, row: 0)), mode: .explicitOnly)
        #expect(link == "https://example.com")
    }

    @Test func testTypedExplicitLinkIncludesMetadataAndRange() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 10, rows: 1))
        terminal.feed(text: "abc")

        let atom = TinyAtom.lookup(value: "id=docs:role=help;https://example.com")!
        let line = terminal.displayBuffer.lines[0]
        var cd = line[1]
        cd.setPayload(atom: atom)
        line[1] = cd

        let link = terminal.terminalLink(
            at: .buffer(Position(col: 1, row: 0)),
            mode: .explicitOnly
        )
        #expect(link?.target == "https://example.com")
        #expect(link?.displayedText == "b")
        #expect(link?.kind == .explicit)
        #expect(link?.parameters == ["id": "docs", "role": "help"])
        #expect(link?.ranges == [TerminalLinkRange(row: 0, columns: 1..<2)])
    }

    @Test func testTypedExplicitLinkIncludesWrappedLabelRanges() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 8, rows: 3))
        terminal.feed(text: "\u{1b}]8;id=wrapped;https://example.com\u{1b}\\abcdefghijk\u{1b}]8;;\u{1b}\\")

        let link = terminal.terminalLink(
            at: .buffer(Position(col: 1, row: 1)),
            mode: .explicitOnly
        )
        #expect(link?.target == "https://example.com")
        #expect(link?.displayedText == "abcdefghijk")
        #expect(link?.ranges == [
            TerminalLinkRange(row: 0, columns: 0..<8),
            TerminalLinkRange(row: 1, columns: 0..<3)
        ])
    }

    @Test func testImplicitUrlLookup() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 40, rows: 1))
        terminal.feed(text: "https://example.com tail")

        let link = terminal.link(at: .buffer(Position(col: 5, row: 0)), mode: .explicitAndImplicit)
        #expect(link == "https://example.com")
    }

    @Test func testImplicitFilePathLookup() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 30, rows: 1))
        terminal.feed(text: "/tmp/example.txt")

        let link = terminal.link(at: .buffer(Position(col: 2, row: 0)), mode: .explicitAndImplicit)
        #expect(link == "/tmp/example.txt")
    }

    @Test func testImplicitUrlLookupAcrossWrappedLines() {
        let url = "https://example.com/path"
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 8, rows: 4))
        terminal.feed(text: url)

        let topRowLink = terminal.link(at: .buffer(Position(col: 2, row: 0)), mode: .explicitAndImplicit)
        #expect(topRowLink == url)

        let wrappedRowLink = terminal.link(at: .buffer(Position(col: 1, row: 1)), mode: .explicitAndImplicit)
        #expect(wrappedRowLink == url)
    }

    @Test func testImplicitLookupP95StaysUnderOneMillisecondWithLargeScrollback() {
        let terminal = Terminal(
            delegate: self,
            options: TerminalOptions(cols: 80, rows: 24, scrollback: 10_100)
        )
        for index in 0..<10_000 {
            terminal.feed(text: "history line \(index)\r\n")
        }
        terminal.feed(text: "https://example.com/performance")
        let location = Terminal.LinkLookupLocation.screen(Position(col: 10, row: 23))

        _ = terminal.terminalLink(at: location, mode: .explicitAndImplicit)
        var samples: [UInt64] = []
        for _ in 0..<200 {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = terminal.terminalLink(at: location, mode: .explicitAndImplicit)
            samples.append(DispatchTime.now().uptimeNanoseconds - start)
        }
        samples.sort()
        let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
        print("SwiftTerm implicit-link lookup p95: \(p95) ns")
        #expect(p95 < 1_000_000)
    }

    @Test func testImplicitMatchReportsPerRowRangesAcrossWrap() {
        let url = "https://example.com/path"
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 8, rows: 4))
        terminal.feed(text: url)

        guard let match = terminal.linkMatch(at: .buffer(Position(col: 1, row: 1)), mode: .explicitAndImplicit) else {
            Issue.record("Expected implicit link match on wrapped row")
            return
        }
        #expect(match.text == url)
        #expect(match.rowRanges.count >= 2)
        #expect(match.rowRanges.contains { $0.row == 0 })
        #expect(match.rowRanges.contains { $0.row == 1 })
        #expect(match.rowRanges.first(where: { $0.row == 1 })?.range.contains(1) == true)
    }

    @Test func testImplicitUrlLookupAcrossWrappedContinuationWithIndentation() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 20, rows: 3))
        write("https://example.", terminal: terminal, row: 0)
        write("    com/path", terminal: terminal, row: 1)
        terminal.displayBuffer.lines[1].isWrapped = true

        let wrappedRowLink = terminal.link(at: .buffer(Position(col: 6, row: 1)), mode: .explicitAndImplicit)
        #expect(wrappedRowLink == "https://example.com/path")
    }

    @Test func testImplicitUrlLookupAcrossEditorSoftWrapWithoutWrappedFlag() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 92, rows: 4))
        let firstSegment = "https://example.com/this/is/a/long/url/segment/that/reaches/the/visual/wrap/"
        write(firstSegment, terminal: terminal, row: 0)
        write("    and/keeps/going", terminal: terminal, row: 1)

        let firstRowLink = terminal.link(at: .buffer(Position(col: 20, row: 0)), mode: .explicitAndImplicit)
        #expect(firstRowLink == firstSegment + "and/keeps/going")

        let wrappedRowLink = terminal.link(at: .buffer(Position(col: 8, row: 1)), mode: .explicitAndImplicit)
        #expect(wrappedRowLink == firstSegment + "and/keeps/going")
    }

    @Test func testImplicitUrlLookupDoesNotJoinUnrelatedRows() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 92, rows: 3))
        write("https://example.com", terminal: terminal, row: 0)
        write("nextline", terminal: terminal, row: 1)

        let urlRowLink = terminal.link(at: .buffer(Position(col: 10, row: 0)), mode: .explicitAndImplicit)
        #expect(urlRowLink == "https://example.com")

        let nextRowLink = terminal.link(at: .buffer(Position(col: 2, row: 1)), mode: .explicitAndImplicit)
        #expect(nextRowLink == nil)
    }

    @Test func testImplicitBareDomainDoesNotMatch() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 30, rows: 1))
        terminal.feed(text: "example.com")

        let link = terminal.link(at: .buffer(Position(col: 3, row: 0)), mode: .explicitAndImplicit)
        #expect(link == nil)
    }

    @Test func testWhitespaceReturnsNil() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 10, rows: 1))
        terminal.feed(text: "a b")

        let link = terminal.link(at: .buffer(Position(col: 1, row: 0)), mode: .explicitAndImplicit)
        #expect(link == nil)
    }

    @Test func testScreenCoordinates() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 32, rows: 2))
        terminal.feed(text: "https://www.example.com")

        let link = terminal.link(at: .screen(Position(col: 10, row: 0)), mode: .explicitAndImplicit)
        #expect(link == "https://www.example.com")
    }
}
