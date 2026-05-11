//
//  PrivateSequenceHookTests.swift
//
//  Tests for the generic private OSC/APC/DCS extension hook used by
//  VectorTerminal and other embedders that need protocol-specific graphics
//  extensions without hard-coding those protocols into SwiftTerm core.
//
#if os(macOS)
import Foundation
import Testing

@testable import SwiftTerm

final class PrivateSequenceHookTests {
    private let esc = "\u{1b}"
    private let bel = "\u{07}"

    @Test func unhandledOSCDispatchesToPrivateSequenceHandler() {
        let (terminal, _) = TerminalTestHarness.makeTerminal()
        var received: [TerminalPrivateSequence] = []

        terminal.registerPrivateSequenceHandler { sequence in
            received.append(sequence)
            return true
        }

        terminal.feed(text: "\(esc)]999;hello vector\(bel)")

        #expect(received.count == 1)
        #expect(received.first?.kind == .osc)
        #expect(received.first?.command == 999)
        #expect(text(from: received.first?.data) == "hello vector")
    }

    @Test func knownOSCUsesExistingHandlerBeforePrivateSequenceHandler() {
        let delegate = TitleDelegate()
        let terminal = Terminal(
            delegate: delegate,
            options: TerminalOptions(cols: 80, rows: 24, scrollback: 0)
        )
        var received: [TerminalPrivateSequence] = []

        terminal.registerPrivateSequenceHandler { sequence in
            received.append(sequence)
            return true
        }

        terminal.feed(text: "\(esc)]0;Vector Terminal\(bel)")

        #expect(delegate.titles == ["Vector Terminal"])
        #expect(received.isEmpty)
    }

    @Test func unhandledAPCDispatchesToPrivateSequenceHandler() {
        let (terminal, _) = TerminalTestHarness.makeTerminal()
        var received: [TerminalPrivateSequence] = []

        terminal.registerPrivateSequenceHandler { sequence in
            received.append(sequence)
            return true
        }

        terminal.feed(text: "\(esc)_VTG;capabilities?\(esc)\\")

        #expect(received.count == 1)
        #expect(received.first?.kind == .apc)
        #expect(received.first?.command == Int(UInt8(ascii: "V")))
        #expect(text(from: received.first?.data) == "TG;capabilities?")
    }

    @Test func unhandledDCSDispatchesToPrivateSequenceHandler() {
        let (terminal, _) = TerminalTestHarness.makeTerminal()
        var received: [TerminalPrivateSequence] = []

        terminal.registerPrivateSequenceHandler { sequence in
            received.append(sequence)
            return true
        }

        terminal.feed(text: "\(esc)P12;34zpayload\(esc)\\")

        #expect(received.count == 1)
        #expect(received.first?.kind == .dcs)
        #expect(received.first?.command == Int(UInt8(ascii: "z")))
        #expect(received.first?.parameters == [12, 34])
        #expect(received.first?.intermediates.isEmpty == true)
        #expect(text(from: received.first?.data) == "payload")
    }

    @Test func unhandledDCSPreservesIntermediatesAndParameters() {
        let (terminal, _) = TerminalTestHarness.makeTerminal()
        var received: [TerminalPrivateSequence] = []

        terminal.registerPrivateSequenceHandler { sequence in
            received.append(sequence)
            return true
        }

        terminal.feed(text: "\(esc)P7$zbody\(esc)\\")

        #expect(received.count == 1)
        #expect(received.first?.kind == .dcs)
        #expect(received.first?.command == Int(UInt8(ascii: "z")))
        #expect(received.first?.parameters == [7])
        #expect(received.first?.intermediates == [UInt8(ascii: "$")])
        #expect(text(from: received.first?.data) == "body")
    }

    private func text(from data: ArraySlice<UInt8>?) -> String? {
        guard let data else {
            return nil
        }
        return String(bytes: data, encoding: .utf8)
    }
}

private final class TitleDelegate: TerminalDelegate {
    private(set) var titles: [String] = []

    func setTerminalTitle(source: Terminal, title: String) {
        titles.append(title)
    }

    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
#endif
