import Foundation
import Testing

@testable import SwiftTerm

final class VectorTerminalGraphicsParserContentTests {
    @Test func parserPreservesSemicolonsInsidePayload() {
        let command = parseSingleVTGRawCommand("path,id=multi,stroke=#22c55e;M 0 0; L 10 10; Z")

        #expect(command == VectorTerminalGraphicsCommand(
            name: "path",
            parameters: ["id": "multi", "stroke": "#22c55e"],
            payload: "M 0 0; L 10 10; Z"
        ))
    }

    @Test func parserIgnoresFieldsWithoutKeyValuePairs() {
        let command = parseSingleVTGRawCommand("line,id=a,,x1=1,malformed,y1=2,empty=")

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
}
