import Foundation

extension VTGPrimitive {
    /// SVG fill attributes for optional VTG fills.
    func svgFill(_ color: VTGColor?) -> String {
        guard let color else {
            return " fill=\"none\""
        }
        return " fill=\"\(color.svgColor)\" fill-opacity=\"\(svgNumber(color.alpha))\""
    }

    /// SVG stroke attributes for optional VTG strokes.
    func svgStroke(_ color: VTGColor?, width: Double, lineCap: VTGLineCap? = nil, lineJoin: VTGLineJoin? = nil) -> String {
        guard let color else {
            return ""
        }
        let cap = lineCap.map { " stroke-linecap=\"\($0.rawValue)\"" } ?? ""
        let join = lineJoin.map { " stroke-linejoin=\"\($0.rawValue)\"" } ?? ""
        return " stroke=\"\(color.svgColor)\" stroke-opacity=\"\(svgNumber(color.alpha))\" stroke-width=\"\(svgNumber(width))\"\(cap)\(join)"
    }

}

extension VTGCurve {
    var svgPathData: String {
        switch self {
        case .quadratic(let start, let control, let end):
            return "M \(svgNumber(start.x)) \(svgNumber(start.y)) Q \(svgNumber(control.x)) \(svgNumber(control.y)) \(svgNumber(end.x)) \(svgNumber(end.y))"
        case .cubic(let start, let control1, let control2, let end):
            return "M \(svgNumber(start.x)) \(svgNumber(start.y)) C \(svgNumber(control1.x)) \(svgNumber(control1.y)) \(svgNumber(control2.x)) \(svgNumber(control2.y)) \(svgNumber(end.x)) \(svgNumber(end.y))"
        }
    }
}

extension [VTGPathCommand] {
    var svgPathData: String {
        map { command in
            switch command {
            case .move(let point):
                return "M \(svgNumber(point.x)) \(svgNumber(point.y))"
            case .line(let point):
                return "L \(svgNumber(point.x)) \(svgNumber(point.y))"
            case .quadratic(let control, let end):
                return "Q \(svgNumber(control.x)) \(svgNumber(control.y)) \(svgNumber(end.x)) \(svgNumber(end.y))"
            case .cubic(let control1, let control2, let end):
                return "C \(svgNumber(control1.x)) \(svgNumber(control1.y)) \(svgNumber(control2.x)) \(svgNumber(control2.y)) \(svgNumber(end.x)) \(svgNumber(end.y))"
            case .close:
                return "Z"
            }
        }
        .joined(separator: " ")
    }
}

extension VTGColor {
    /// RGB SVG color string; alpha is emitted separately as opacity.
    var svgColor: String {
        let red = UInt8(max(0, min(255, (self.red * 255).rounded())))
        let green = UInt8(max(0, min(255, (self.green * 255).rounded())))
        let blue = UInt8(max(0, min(255, (self.blue * 255).rounded())))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

/// Format SVG numbers compactly while preserving sub-pixel values when needed.
func svgNumber(_ value: Double) -> String {
    let rounded = value.rounded()
    if abs(value - rounded) < 0.001 {
        return String(Int(rounded))
    }
    return String(format: "%.3f", value)
}

/// Escape text payloads for SVG text nodes.
func svgEscapedText(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}
