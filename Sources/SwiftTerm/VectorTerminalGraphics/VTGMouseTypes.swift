import Foundation

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
