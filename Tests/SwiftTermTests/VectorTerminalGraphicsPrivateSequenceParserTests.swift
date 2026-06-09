import Foundation
import Testing

@testable import SwiftTerm

final class VectorTerminalGraphicsPrivateSequenceParserTests {
    @Test func privateSequenceParserAcceptsVTGAPC() {
        let parser = VectorTerminalGraphicsParser()
        let data = bytes("TG;capabilities?")
        let sequence = TerminalPrivateSequence(
            kind: .apc,
            command: Int(UInt8(ascii: "V")),
            data: data[...]
        )

        let command = parser.command(from: sequence)

        #expect(command == VectorTerminalGraphicsCommand(name: "capabilities?"))
    }

    @Test func privateSequenceParserRejectsNonVTGAPC() {
        let parser = VectorTerminalGraphicsParser()
        let data = bytes("not-vtg")
        let sequence = TerminalPrivateSequence(
            kind: .apc,
            command: Int(UInt8(ascii: "X")),
            data: data[...]
        )

        #expect(parser.command(from: sequence) == nil)
    }

    private func bytes(_ value: String) -> [UInt8] {
        Array(value.utf8)
    }
}
