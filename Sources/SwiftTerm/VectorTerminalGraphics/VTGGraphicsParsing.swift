import Foundation

/// Tiny parser for the constrained VTG path grammar.
///
/// Supported commands intentionally mirror the common SVG command names but only
/// absolute coordinates are accepted in this first pass: `M`, `L`, `Q`, `C`,
/// and `Z`.
enum VTGPathParser {
    static func parse(_ payload: String) -> [VTGPathCommand]? {
        let tokens = tokenize(payload)
        guard tokens.isEmpty == false else {
            return nil
        }
        var index = 0
        var commands: [VTGPathCommand] = []

        func nextNumber() -> Double? {
            guard index < tokens.count, let value = Double(tokens[index]) else {
                return nil
            }
            index += 1
            return value
        }

        func nextPoint() -> VTGPoint? {
            guard let x = nextNumber(), let y = nextNumber() else {
                return nil
            }
            return VTGPoint(x: x, y: y)
        }

        while index < tokens.count {
            let token = tokens[index].uppercased()
            index += 1
            switch token {
            case "M":
                guard let point = nextPoint() else { return nil }
                commands.append(.move(to: point))
            case "L":
                guard let point = nextPoint() else { return nil }
                commands.append(.line(to: point))
            case "Q":
                guard let control = nextPoint(), let end = nextPoint() else { return nil }
                commands.append(.quadratic(control: control, end: end))
            case "C":
                guard let control1 = nextPoint(), let control2 = nextPoint(), let end = nextPoint() else { return nil }
                commands.append(.cubic(control1: control1, control2: control2, end: end))
            case "Z":
                commands.append(.close)
            default:
                return nil
            }
        }
        return commands
    }

    private static func tokenize(_ payload: String) -> [String] {
        var expanded = ""
        for character in payload {
            if "MLQCZmlqcz".contains(character) {
                expanded.append(" ")
                expanded.append(character)
                expanded.append(" ")
            } else if character == "," || character.isWhitespace {
                expanded.append(" ")
            } else {
                expanded.append(character)
            }
        }
        return expanded.split(separator: " ").map(String.init)
    }
}

extension VectorTerminalGraphicsCommand {
    /// Read a numeric command parameter, returning a harmless default when the
    /// child application sends malformed input.
    func double(_ key: String, default defaultValue: Double = 0) -> Double {
        guard let raw = parameters[key], let value = Double(raw) else {
            return defaultValue
        }
        return value
    }

    /// Read a normalized numeric command parameter for sprite anchors.
    func normalizedDouble(_ key: String, default defaultValue: Double) -> Double {
        min(1, max(0, double(key, default: defaultValue)))
    }

    /// Parse an optional color parameter where `"none"` means transparent.
    func color(_ key: String) -> VTGColor? {
        guard let raw = parameters[key], raw != "none" else {
            return nil
        }
        return VTGColor(hex: raw)
    }

    /// Read and clamp a VTG layer parameter.
    func layerValue(default defaultValue: Int) -> Int {
        let raw = parameters["layer"] ?? parameters["value"]
        guard let raw, let value = Int(raw) else {
            return defaultValue
        }
        return VTGLayerModel.clamped(value)
    }

    /// Parse optional stroke endpoint style. Unknown values are ignored so
    /// older or typo-prone clients do not poison retained scene state.
    func lineCap() -> VTGLineCap? {
        parameters["lineCap"].flatMap(VTGLineCap.init(rawValue:))
    }

    /// Parse optional stroke corner style. Unknown values are ignored so the
    /// renderer falls back to each primitive's historical default.
    func lineJoin() -> VTGLineJoin? {
        parameters["lineJoin"].flatMap(VTGLineJoin.init(rawValue:))
    }
}

extension VTGColor {
    /// Initialize from `#RRGGBB` or `#RRGGBBAA`.
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6 || raw.count == 8, let value = UInt64(raw, radix: 16) else {
            return nil
        }
        if raw.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xff) / 255,
                green: Double((value >> 8) & 0xff) / 255,
                blue: Double(value & 0xff) / 255,
                alpha: 1
            )
        } else {
            self.init(
                red: Double((value >> 24) & 0xff) / 255,
                green: Double((value >> 16) & 0xff) / 255,
                blue: Double((value >> 8) & 0xff) / 255,
                alpha: Double(value & 0xff) / 255
            )
        }
    }
}
