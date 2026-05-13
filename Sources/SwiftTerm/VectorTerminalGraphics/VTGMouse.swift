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

/// VTG mouse reporting modes requested by child applications.
public enum VTGMouseMode: String, Equatable {
    case click
    case raw
    case drag
    case all

    public var emitsRawMouse: Bool {
        self == .raw || self == .drag || self == .all
    }

    public var emitsScroll: Bool {
        self == .raw || self == .drag || self == .all
    }
}

/// VTG mouse event kinds emitted by a host terminal.
public enum VTGMouseEventType: String, Equatable {
    case down
    case up
    case drag
    case click
    case scroll
}

/// Keyboard modifiers attached to a VTG mouse event.
public struct VTGMouseModifiers: OptionSet, Equatable {
    public let rawValue: Int

    public static let shift = VTGMouseModifiers(rawValue: 1 << 0)
    public static let control = VTGMouseModifiers(rawValue: 1 << 1)
    public static let alt = VTGMouseModifiers(rawValue: 1 << 2)
    public static let command = VTGMouseModifiers(rawValue: 1 << 3)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Compact wire representation used in VTG mouse responses.
    public var wireValue: String {
        var names: [String] = []
        if contains(.shift) {
            names.append("shift")
        }
        if contains(.control) {
            names.append("ctrl")
        }
        if contains(.alt) {
            names.append("alt")
        }
        if contains(.command) {
            names.append("cmd")
        }
        return names.isEmpty ? "none" : names.joined(separator: "|")
    }
}

/// Mouse position in VTG pixel coordinates and terminal cell coordinates.
public struct VTGMouseSnapshot: Equatable {
    public var x: Int
    public var y: Int
    public var cellX: Int
    public var cellY: Int
    public var modifiers: String

    public init(x: Int, y: Int, cellX: Int, cellY: Int, modifiers: String) {
        self.x = x
        self.y = y
        self.cellX = cellX
        self.cellY = cellY
        self.modifiers = modifiers
    }

    public init(x: Int, y: Int, cellX: Int, cellY: Int, modifiers: VTGMouseModifiers) {
        self.init(x: x, y: y, cellX: cellX, cellY: cellY, modifiers: modifiers.wireValue)
    }
}

/// Terminal cell and pixel position for a mouse event.
public struct VTGMouseCellPosition: Equatable {
    /// Zero-based terminal column.
    public var gridCol: Int
    /// Zero-based terminal row, measured from the top.
    public var gridRow: Int
    /// Clamped pixel x coordinate.
    public var pixelX: Int
    /// Clamped pixel y coordinate, measured from the top.
    public var pixelY: Int

    public init(gridCol: Int, gridRow: Int, pixelX: Int, pixelY: Int) {
        self.gridCol = gridCol
        self.gridRow = gridRow
        self.pixelX = pixelX
        self.pixelY = pixelY
    }
}

/// Maps VTG pixel coordinates into terminal grid cells.
public struct VTGMouseCoordinateMapper: Equatable {
    public var columns: Int
    public var rows: Int
    public var canvasWidth: Double
    public var canvasHeight: Double

    public init(columns: Int, rows: Int, canvasWidth: Double, canvasHeight: Double) {
        self.columns = columns
        self.rows = rows
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }

    /// Return the clamped zero-based cell and pixel position for top-left-origin pixels.
    public func cellPosition(pixelX: Double, pixelY: Double) -> VTGMouseCellPosition? {
        guard columns > 0, rows > 0, canvasWidth > 0, canvasHeight > 0 else {
            return nil
        }
        let clampedX = min(max(pixelX, 0), canvasWidth)
        let clampedY = min(max(pixelY, 0), canvasHeight)
        let cellWidth = canvasWidth / Double(columns)
        let cellHeight = canvasHeight / Double(rows)
        guard cellWidth > 0, cellHeight > 0 else {
            return nil
        }

        let col = min(max(0, Int(clampedX / cellWidth)), columns - 1)
        let row = min(max(0, Int(clampedY / cellHeight)), rows - 1)
        return VTGMouseCellPosition(
            gridCol: col,
            gridRow: row,
            pixelX: Int(clampedX),
            pixelY: Int(clampedY)
        )
    }

    /// Return a VTG mouse snapshot using one-based cell coordinates for the wire protocol.
    public func snapshot(pixelX: Double, pixelY: Double, modifiers: String) -> VTGMouseSnapshot? {
        guard let position = cellPosition(pixelX: pixelX, pixelY: pixelY) else {
            return nil
        }
        return VTGMouseSnapshot(
            x: position.pixelX,
            y: position.pixelY,
            cellX: position.gridCol + 1,
            cellY: position.gridRow + 1,
            modifiers: modifiers
        )
    }

    /// Return a VTG mouse snapshot using typed modifiers.
    public func snapshot(pixelX: Double, pixelY: Double, modifiers: VTGMouseModifiers) -> VTGMouseSnapshot? {
        snapshot(pixelX: pixelX, pixelY: pixelY, modifiers: modifiers.wireValue)
    }
}

/// Synthesizes one logical click from a platform down/up mouse pair.
///
/// Embedding views still capture native mouse events, but this helper keeps the
/// protocol-level debounce thresholds in SwiftTerm so all VTG hosts behave the
/// same way.
public final class VTGMouseClickSynthesizer {
    private struct DownEvent {
        var button: Int
        var snapshot: VTGMouseSnapshot
        var timestamp: TimeInterval
    }

    public var maximumClickInterval: TimeInterval
    public var maximumClickDistance: Double

    private var downEvent: DownEvent?

    public init(
        maximumClickInterval: TimeInterval = 0.6,
        maximumClickDistance: Double = 8
    ) {
        self.maximumClickInterval = maximumClickInterval
        self.maximumClickDistance = maximumClickDistance
    }

    /// Record a possible click start.
    public func recordDown(
        button: Int,
        snapshot: VTGMouseSnapshot,
        timestamp: TimeInterval
    ) {
        downEvent = DownEvent(button: button, snapshot: snapshot, timestamp: timestamp)
    }

    /// Return true when the recorded down event and this up event form a click.
    public func shouldSynthesizeClick(
        button: Int,
        snapshot: VTGMouseSnapshot,
        timestamp: TimeInterval
    ) -> Bool {
        guard let downEvent,
              downEvent.button == button else {
            return false
        }
        let elapsed = timestamp - downEvent.timestamp
        let distance = hypot(
            Double(snapshot.x - downEvent.snapshot.x),
            Double(snapshot.y - downEvent.snapshot.y)
        )
        return elapsed <= maximumClickInterval && distance <= maximumClickDistance
    }

    /// Clear the current pending down event.
    public func reset() {
        downEvent = nil
    }
}
