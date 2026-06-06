import Foundation
import Testing

@testable import SwiftTerm

struct VTGParserFixture {
    var rawCommand: String
    var expectedName: String
    var expectedParameters: [String: String]
    var expectedPayload: String?

    init(
        _ rawCommand: String,
        name expectedName: String,
        parameters expectedParameters: [String: String] = [:],
        payload expectedPayload: String? = nil
    ) {
        self.rawCommand = rawCommand
        self.expectedName = expectedName
        self.expectedParameters = expectedParameters
        self.expectedPayload = expectedPayload
    }
}

func parseSingleVTGRawCommand(
    _ rawCommand: String,
    payload: String? = nil
) -> VectorTerminalGraphicsCommand? {
    let parser = VectorTerminalGraphicsParser()
    let esc = "\u{1b}"
    let payloadSuffix = payload.map { ";\($0)" } ?? ""
    let result = parser.feed(Array("\(esc)_VTG;\(rawCommand)\(payloadSuffix)\(esc)\\".utf8)[...])
    return result.commands.first
}

func assertParserFixtures(_ fixtures: [VTGParserFixture]) {
    for fixture in fixtures {
        let command = parseSingleVTGRawCommand(
            fixture.rawCommand,
            payload: fixture.expectedPayload
        )

        #expect(command?.name == fixture.expectedName)
        #expect(command?.parameters == fixture.expectedParameters)
        #expect(command?.payload == fixture.expectedPayload)
    }
}
