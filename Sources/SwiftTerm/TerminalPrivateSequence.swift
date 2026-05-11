import Foundation

/// String-control sequence kind exposed to embedders.
public enum TerminalPrivateSequenceKind: Equatable {
    /// Operating System Command.
    case osc

    /// Application Program Command.
    case apc

    /// Device Control String.
    case dcs
}

/// A private or extension sequence received by the terminal parser.
///
/// SwiftTerm uses this as an extension point for embedders that need to consume
/// application-specific control sequences without hard-coding those protocols
/// into the terminal emulator.
public struct TerminalPrivateSequence {
    public let kind: TerminalPrivateSequenceKind
    public let command: Int
    public let data: ArraySlice<UInt8>
    public let intermediates: [UInt8]
    public let parameters: [Int]

    public init(
        kind: TerminalPrivateSequenceKind,
        command: Int,
        data: ArraySlice<UInt8>,
        intermediates: [UInt8] = [],
        parameters: [Int] = []
    ) {
        self.kind = kind
        self.command = command
        self.data = data
        self.intermediates = intermediates
        self.parameters = parameters
    }
}

/// Return `true` when the sequence was consumed.
public typealias TerminalPrivateSequenceHandler = (TerminalPrivateSequence) -> Bool
