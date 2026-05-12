import Foundation

/// Result of separating VectorTerminal Graphics commands from terminal bytes.
///
/// `terminalBytes` are bytes that should continue through SwiftTerm's normal
/// terminal parser. `commands` contains complete VTG APC commands that an
/// embedder or future SwiftTerm-hosted graphics plane can handle separately.
public struct VectorTerminalGraphicsParseResult: Equatable {
    public var terminalBytes: [UInt8]
    public var commands: [VectorTerminalGraphicsCommand]

    public init(
        terminalBytes: [UInt8],
        commands: [VectorTerminalGraphicsCommand]
    ) {
        self.terminalBytes = terminalBytes
        self.commands = commands
    }
}

/// Parsed representation of one `ESC _ VTG;... ESC \` graphics command.
public struct VectorTerminalGraphicsCommand: Equatable {
    /// Command name, such as `line`, `rect`, `capabilities?`, or `mouseEvents`.
    public var name: String

    /// Comma-separated `key=value` fields parsed from the command header.
    public var parameters: [String: String]

    /// Optional semicolon payload following the command header.
    public var payload: String?

    public init(
        name: String,
        parameters: [String: String] = [:],
        payload: String? = nil
    ) {
        self.name = name
        self.parameters = parameters
        self.payload = payload
    }
}

/// Incremental parser for VectorTerminal Graphics APC sequences.
///
/// VTG uses the ANSI APC string-control envelope:
///
/// ```text
/// ESC _ VTG;<command>[,<key>=<value>...][;<payload>] ESC \
/// ```
///
/// Child processes can split a control string across arbitrary writes, so the
/// parser buffers an incomplete VTG sequence until the `ESC \` terminator
/// arrives. Non-VTG bytes are preserved exactly so normal terminal rendering is
/// unaffected.
public final class VectorTerminalGraphicsParser {
    private var buffer: [UInt8] = []
    private let esc: UInt8 = 0x1b

    public init() {}

    /// Clear any buffered partial VTG sequence.
    public func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    /// Consume raw terminal bytes and split out complete VTG commands.
    public func feed(_ bytes: ArraySlice<UInt8>) -> VectorTerminalGraphicsParseResult {
        buffer.append(contentsOf: bytes)
        var terminalBytes: [UInt8] = []
        var commands: [VectorTerminalGraphicsCommand] = []

        while !buffer.isEmpty {
            guard let start = findVTGStart(in: buffer) else {
                terminalBytes.append(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                break
            }

            if start > 0 {
                terminalBytes.append(contentsOf: buffer[..<start])
                buffer.removeFirst(start)
            }

            guard let end = findStringTerminator(in: buffer, from: 0) else {
                // Keep the partial sequence for a later feed. This is the
                // common case when a PTY splits an APC over multiple reads.
                break
            }

            let sequence = Array(buffer[0...end])
            buffer.removeFirst(end + 1)

            if let command = parseVTGSequence(sequence) {
                commands.append(command)
            }
        }

        return VectorTerminalGraphicsParseResult(
            terminalBytes: terminalBytes,
            commands: commands
        )
    }

    /// Parse a SwiftTerm private APC callback into a VTG command.
    ///
    /// SwiftTerm's private-sequence hook has already removed `ESC _` and the
    /// string terminator. For VTG, the APC command byte is `V` and the remaining
    /// data starts with `TG;`.
    public func command(from sequence: TerminalPrivateSequence) -> VectorTerminalGraphicsCommand? {
        guard sequence.kind == .apc,
              sequence.command == UInt8(ascii: "V"),
              sequence.data.starts(with: [
                  UInt8(ascii: "T"),
                  UInt8(ascii: "G"),
                  UInt8(ascii: ";")
              ]) else {
            return nil
        }

        let contentBytes = sequence.data.dropFirst(3)
        guard let content = String(bytes: contentBytes, encoding: .utf8) else {
            return nil
        }
        return parseContent(content)
    }

    private func findVTGStart(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 7 else {
            return nil
        }
        for index in 0...(bytes.count - 7) {
            if bytes[index] == esc,
               bytes[index + 1] == UInt8(ascii: "_"),
               bytes[index + 2] == UInt8(ascii: "V"),
               bytes[index + 3] == UInt8(ascii: "T"),
               bytes[index + 4] == UInt8(ascii: "G"),
               bytes[index + 5] == UInt8(ascii: ";") {
                return index
            }
        }
        return nil
    }

    private func findStringTerminator(in bytes: [UInt8], from start: Int) -> Int? {
        guard bytes.count >= 2 else {
            return nil
        }

        var index = start
        while index + 1 < bytes.count {
            if bytes[index] == esc && bytes[index + 1] == UInt8(ascii: "\\") {
                return index + 1
            }
            index += 1
        }
        return nil
    }

    private func parseVTGSequence(_ sequence: [UInt8]) -> VectorTerminalGraphicsCommand? {
        guard sequence.count >= 9 else {
            return nil
        }

        let contentBytes = sequence.dropFirst(6).dropLast(2)
        guard let content = String(bytes: contentBytes, encoding: .utf8) else {
            return nil
        }
        return parseContent(content)
    }

    private func parseContent(_ content: String) -> VectorTerminalGraphicsCommand? {
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
