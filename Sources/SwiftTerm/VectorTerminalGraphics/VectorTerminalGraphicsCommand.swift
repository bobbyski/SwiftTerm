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
