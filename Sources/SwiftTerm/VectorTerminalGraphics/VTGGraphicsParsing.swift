import Foundation

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
