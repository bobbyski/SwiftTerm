import Foundation

/// Command-content parsing helpers for `VectorTerminalGraphicsParser`.
extension VectorTerminalGraphicsParser {
    func parseVTGSequence(_ sequence: [UInt8]) -> VectorTerminalGraphicsCommand? {
        guard sequence.count >= 9 else {
            return nil
        }

        let contentBytes = sequence.dropFirst(6).dropLast(2)
        guard let content = String(bytes: contentBytes, encoding: .utf8) else {
            return nil
        }
        return parseContent(content)
    }

    func parseContent(_ content: String) -> VectorTerminalGraphicsCommand? {
        let parts = content.split(
            separator: ";",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let commandPart = String(parts.first ?? "")
        let payload = parts.count > 1 ? String(parts[1]) : nil
        let fields = commandPart.split(
            separator: ",",
            omittingEmptySubsequences: false
        ).map(String.init)

        guard let name = fields.first, !name.isEmpty else {
            return nil
        }

        var parameters: [String: String] = [:]
        for field in fields.dropFirst() {
            let pair = field.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            guard pair.count == 2 else {
                continue
            }
            parameters[String(pair[0])] = String(pair[1])
        }

        return VectorTerminalGraphicsCommand(
            name: name,
            parameters: parameters,
            payload: payload
        )
    }
}
