import Foundation

extension VTGPrimitive {
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

    private func distance(from start: VTGPoint, to end: VTGPoint) -> Double {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func point(from start: VTGPoint, toward end: VTGPoint, distance: Double) -> VTGPoint {
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
