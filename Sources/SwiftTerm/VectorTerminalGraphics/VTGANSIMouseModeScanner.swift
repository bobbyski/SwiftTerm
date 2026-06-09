import Foundation

/// ANSI mouse mode toggles that a child process can request with DEC private modes.
public enum VTGANSIMouseModeSequence: Equatable {
    /// VT200-style mouse press/release reporting: `ESC[?1000h` / `ESC[?1000l`.
    case vt200(enabled: Bool)
    /// SGR coordinate encoding: `ESC[?1006h` / `ESC[?1006l`.
    case sgr(enabled: Bool)
    /// SGR pixel-coordinate encoding: `ESC[?1016h` / `ESC[?1016l`.
    case pixel(enabled: Bool)

    /// Whether this sequence directly toggles basic mouse reporting.
    public var basicMouseReportingEnabled: Bool? {
        guard case let .vt200(enabled) = self else {
            return nil
        }
        return enabled
    }

    /// Human-readable diagnostic label for logs and debugger views.
    public var diagnosticDescription: String {
        switch self {
        case let .vt200(enabled):
            return "child \(enabled ? "enabled" : "disabled") VT200 mouse reporting: ESC[?1000\(enabled ? "h" : "l")"
        case let .sgr(enabled):
            return "child \(enabled ? "enabled" : "disabled") SGR mouse reporting: ESC[?1006\(enabled ? "h" : "l")"
        case let .pixel(enabled):
            return "child \(enabled ? "enabled" : "disabled") pixel mouse reporting: ESC[?1016\(enabled ? "h" : "l")"
        }
    }
}

/// Scans child output for ANSI mouse mode toggles.
///
/// SwiftTerm already parses these modes internally for normal terminal mouse
/// support. VTG embedders also need a small reusable scanner because a host
/// view may bridge native platform mouse events before SwiftTerm's built-in
/// event path sees them.
public enum VTGANSIMouseModeScanner {
    private struct Pattern {
        var text: String
        var sequence: VTGANSIMouseModeSequence
    }

    private static let patterns: [Pattern] = [
        Pattern(text: "\u{1B}[?1000h", sequence: .vt200(enabled: true)),
        Pattern(text: "\u{1B}[?1000l", sequence: .vt200(enabled: false)),
        Pattern(text: "\u{1B}[?1006h", sequence: .sgr(enabled: true)),
        Pattern(text: "\u{1B}[?1006l", sequence: .sgr(enabled: false)),
        Pattern(text: "\u{1B}[?1016h", sequence: .pixel(enabled: true)),
        Pattern(text: "\u{1B}[?1016l", sequence: .pixel(enabled: false))
    ]

    /// Return mouse mode sequences found in the byte stream, preserving stream order.
    public static func scan(_ bytes: [UInt8]) -> [VTGANSIMouseModeSequence] {
        guard let text = String(bytes: bytes, encoding: .utf8) else {
            return []
        }

        var matches: [(index: String.Index, sequence: VTGANSIMouseModeSequence)] = []
        for pattern in patterns {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: pattern.text, range: searchRange) {
                matches.append((range.lowerBound, pattern.sequence))
                searchRange = range.upperBound..<text.endIndex
            }
        }

        return matches
            .sorted { $0.index < $1.index }
            .map(\.sequence)
    }
}
