import Foundation
import Testing

@testable import SwiftTerm

final class VectorTerminalGraphicsParserTests {
    private let esc = "\u{1b}"

    @Test func rawParserExtractsCompleteVTGCommand() {
        let parser = VectorTerminalGraphicsParser()
        let bytes = bytes("before\(esc)_VTG;line,id=a,x1=1,y1=2,x2=3,y2=4,width=5;payload\(esc)\\after")

        let result = parser.feed(bytes[...])

        #expect(String(bytes: result.terminalBytes, encoding: .utf8) == "beforeafter")
        #expect(result.commands == [
            VectorTerminalGraphicsCommand(
                name: "line",
                parameters: [
                    "id": "a",
                    "x1": "1",
                    "y1": "2",
                    "x2": "3",
                    "y2": "4",
                    "width": "5"
                ],
                payload: "payload"
            )
        ])
    }

    @Test func rawParserBuffersSplitVTGCommand() {
        let parser = VectorTerminalGraphicsParser()
        let first = parser.feed(bytes("alpha\(esc)_VTG;rect,id=box,x=1")[...])
        let second = parser.feed(bytes(",y=2,w=3,h=4\(esc)\\omega")[...])

        #expect(String(bytes: first.terminalBytes, encoding: .utf8) == "alpha")
        #expect(first.commands.isEmpty)
        #expect(String(bytes: second.terminalBytes, encoding: .utf8) == "omega")
        #expect(second.commands.first?.name == "rect")
        #expect(second.commands.first?.parameters["id"] == "box")
        #expect(second.commands.first?.parameters["h"] == "4")
    }

    @Test func rawParserLeavesIncompleteVTGBufferedUntilReset() {
        let parser = VectorTerminalGraphicsParser()
        let first = parser.feed(bytes("\(esc)_VTG;text,id=label,value=hello")[...])

        #expect(first.terminalBytes.isEmpty)
        #expect(first.commands.isEmpty)

        parser.reset()
        let second = parser.feed(bytes("visible")[...])

        #expect(String(bytes: second.terminalBytes, encoding: .utf8) == "visible")
        #expect(second.commands.isEmpty)
    }

    @Test func rawParserPassesNonVTGAPCThrough() {
        let parser = VectorTerminalGraphicsParser()
        let input = bytes("\(esc)_ABC;ignored\(esc)\\")

        let result = parser.feed(input[...])

        #expect(result.terminalBytes == input)
        #expect(result.commands.isEmpty)
    }

    @Test func parserPreservesSemicolonsInsidePayload() {
        let command = parseSingleRawCommand("path,id=multi,stroke=#22c55e;M 0 0; L 10 10; Z")

        #expect(command == VectorTerminalGraphicsCommand(
            name: "path",
            parameters: ["id": "multi", "stroke": "#22c55e"],
            payload: "M 0 0; L 10 10; Z"
        ))
    }

    @Test func parserIgnoresFieldsWithoutKeyValuePairs() {
        let command = parseSingleRawCommand("line,id=a,,x1=1,malformed,y1=2,empty=")

        #expect(command == VectorTerminalGraphicsCommand(
            name: "line",
            parameters: [
                "id": "a",
                "x1": "1",
                "y1": "2",
                "empty": ""
            ]
        ))
    }

    private func parseSingleRawCommand(_ rawCommand: String) -> VectorTerminalGraphicsCommand? {
        parseSingleRawCommand(rawCommand, payload: nil)
    }

    private func parseSingleRawCommand(
        _ rawCommand: String,
        payload: String?
    ) -> VectorTerminalGraphicsCommand? {
        let parser = VectorTerminalGraphicsParser()
        let payloadSuffix = payload.map { ";\($0)" } ?? ""
        let result = parser.feed(bytes("\(esc)_VTG;\(rawCommand)\(payloadSuffix)\(esc)\\")[...])
        return result.commands.first
    }

    private func bytes(_ value: String) -> [UInt8] {
        Array(value.utf8)
    }
}
