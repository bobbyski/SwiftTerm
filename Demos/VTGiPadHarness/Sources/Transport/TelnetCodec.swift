import Foundation

/// Telnet's NVT layer: enough of RFC 854/1073/1091 to be a terminal.
///
/// A byte stream with IAC escapes in it, not a protocol with a handshake —
/// so this is a codec, not a state machine with a connection inside it. The
/// transport owns the socket and hands bytes here.
///
/// SwiftTerm3270 already does this for TN3270E (`Telnet/TelnetEngine.swift`);
/// this is the plain-terminal half, kept separate because the 3270 engine
/// speaks in records and a VT speaks in bytes.
struct TelnetCodec {
    // Commands
    static let IAC: UInt8 = 255
    static let DONT: UInt8 = 254
    static let DO: UInt8 = 253
    static let WONT: UInt8 = 252
    static let WILL: UInt8 = 251
    static let SB: UInt8 = 250
    static let SE: UInt8 = 240

    // Options
    static let optionEcho: UInt8 = 1
    static let optionSuppressGoAhead: UInt8 = 3
    static let optionTerminalType: UInt8 = 24
    static let optionWindowSize: UInt8 = 31      // NAWS

    /// What the terminal calls itself when the far end asks.
    var terminalType = "xterm-256color"
    var cols = 80
    var rows = 24

    private enum State {
        case data
        case command                     // IAC seen
        case negotiating(UInt8)          // DO/DONT/WILL/WONT seen
        case subnegotiation              // SB seen
        case subnegotiationIAC           // IAC inside SB
    }

    private var state: State = .data
    private var subnegotiation: [UInt8] = []

    /// Split incoming bytes into terminal data and bytes to write back.
    ///
    /// Negotiation is answered here rather than surfaced, because there is
    /// exactly one sensible answer to each of these for a terminal emulator.
    mutating func receive(_ bytes: ArraySlice<UInt8>) -> (data: [UInt8], reply: [UInt8]) {
        var data: [UInt8] = []
        var reply: [UInt8] = []
        data.reserveCapacity(bytes.count)

        for byte in bytes {
            switch state {
            case .data:
                if byte == Self.IAC {
                    state = .command
                } else {
                    data.append(byte)
                }

            case .command:
                switch byte {
                case Self.IAC:
                    data.append(Self.IAC)    // An escaped 255 is a literal 255.
                    state = .data
                case Self.DO, Self.DONT, Self.WILL, Self.WONT:
                    state = .negotiating(byte)
                case Self.SB:
                    subnegotiation = []
                    state = .subnegotiation
                default:
                    state = .data            // GA, NOP and friends: ignored.
                }

            case .negotiating(let command):
                reply.append(contentsOf: answer(command: command, option: byte))
                state = .data

            case .subnegotiation:
                if byte == Self.IAC {
                    state = .subnegotiationIAC
                } else {
                    subnegotiation.append(byte)
                }

            case .subnegotiationIAC:
                if byte == Self.SE {
                    reply.append(contentsOf: answerSubnegotiation())
                    state = .data
                } else {
                    subnegotiation.append(byte)
                    state = .subnegotiation
                }
            }
        }
        return (data, reply)
    }

    /// Escape a 255 the user typed, so it is not read as a command.
    func encode(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        guard bytes.contains(Self.IAC) else {
            return Array(bytes)
        }
        var out: [UInt8] = []
        for byte in bytes {
            out.append(byte)
            if byte == Self.IAC {
                out.append(Self.IAC)
            }
        }
        return out
    }

    /// The window-size subnegotiation: telnet's SIGWINCH.
    func windowSize(cols: Int, rows: Int) -> [UInt8] {
        let width = UInt16(clamping: cols)
        let height = UInt16(clamping: rows)
        return [Self.IAC, Self.SB, Self.optionWindowSize,
                UInt8(width >> 8), UInt8(width & 0xff),
                UInt8(height >> 8), UInt8(height & 0xff),
                Self.IAC, Self.SE]
    }

    // MARK: - Answers

    private func answer(command: UInt8, option: UInt8) -> [UInt8] {
        switch command {
        case Self.DO:
            // What this terminal is willing to do for the far end.
            switch option {
            case Self.optionTerminalType, Self.optionWindowSize, Self.optionSuppressGoAhead:
                var reply = [Self.IAC, Self.WILL, option]
                if option == Self.optionWindowSize {
                    reply += windowSize(cols: cols, rows: rows)
                }
                return reply
            default:
                return [Self.IAC, Self.WONT, option]
            }

        case Self.WILL:
            // What the far end may do. Echo and go-ahead suppression are
            // what a remote shell needs; everything else is declined, which
            // is always safe.
            switch option {
            case Self.optionEcho, Self.optionSuppressGoAhead:
                return [Self.IAC, Self.DO, option]
            default:
                return [Self.IAC, Self.DONT, option]
            }

        case Self.DONT:
            return [Self.IAC, Self.WONT, option]

        case Self.WONT:
            return [Self.IAC, Self.DONT, option]

        default:
            return []
        }
    }

    private func answerSubnegotiation() -> [UInt8] {
        // TERMINAL-TYPE SEND (1) → IS (0) <name>
        guard subnegotiation.first == Self.optionTerminalType,
              subnegotiation.count >= 2,
              subnegotiation[1] == 1 else {
            return []
        }
        return [Self.IAC, Self.SB, Self.optionTerminalType, 0]
            + Array(terminalType.utf8)
            + [Self.IAC, Self.SE]
    }
}
