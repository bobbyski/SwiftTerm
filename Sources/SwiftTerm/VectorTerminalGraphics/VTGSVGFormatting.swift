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

    /// SVG path data for a polygon whose corners are rounded with quadratic
    /// curves through the original vertices. This mirrors the AppKit overlay
    /// renderer so debug snapshots match live output.
    func roundedPolygonPathData(points: [VTGPoint], radius: Double) -> String? {
        guard points.count >= 3 else {
            return nil
        }
        var corners: [(vertex: VTGPoint, start: VTGPoint, end: VTGPoint)] = []
        for index in points.indices {
            let previous = points[(index - 1 + points.count) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let previousDistance = distance(from: current, to: previous)
            let nextDistance = distance(from: current, to: next)
            guard previousDistance > 0, nextDistance > 0 else {
                return nil
            }
            let cornerRadius = min(max(0, radius), previousDistance / 2, nextDistance / 2)
            corners.append((
                vertex: current,
                start: point(from: current, toward: previous, distance: cornerRadius),
                end: point(from: current, toward: next, distance: cornerRadius)
            ))
        }
        guard let first = corners.first else {
            return nil
        }

        var segments = ["M \(svgNumber(first.end.x)) \(svgNumber(first.end.y))"]
        for corner in corners.dropFirst() {
            segments.append("L \(svgNumber(corner.start.x)) \(svgNumber(corner.start.y))")
            segments.append("Q \(svgNumber(corner.vertex.x)) \(svgNumber(corner.vertex.y)) \(svgNumber(corner.end.x)) \(svgNumber(corner.end.y))")
        }
        segments.append("L \(svgNumber(first.start.x)) \(svgNumber(first.start.y))")
        segments.append("Q \(svgNumber(first.vertex.x)) \(svgNumber(first.vertex.y)) \(svgNumber(first.end.x)) \(svgNumber(first.end.y))")
        segments.append("Z")
        return segments.joined(separator: " ")
    }

    func distance(from start: VTGPoint, to end: VTGPoint) -> Double {
        hypot(end.x - start.x, end.y - start.y)
    }

    func point(from start: VTGPoint, toward end: VTGPoint, distance: Double) -> VTGPoint {
        let totalDistance = self.distance(from: start, to: end)
        guard totalDistance > 0 else {
            return start
        }
        let scale = distance / totalDistance
        return VTGPoint(
            x: start.x + (end.x - start.x) * scale,
            y: start.y + (end.y - start.y) * scale
        )
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
