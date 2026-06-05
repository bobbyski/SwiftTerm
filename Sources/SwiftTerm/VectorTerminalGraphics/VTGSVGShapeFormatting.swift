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

    /// SVG path data for a rectangle with VTG's optional per-corner rounding.
    ///
    /// Corner selector digits match the live renderer: 1 top-left, 2
    /// top-right, 3 bottom-right, and 4 bottom-left.
    func roundedRectPathData(x: Double, y: Double, width: Double, height: Double, radius: Double, corners: String?) -> String? {
        guard width > 0, height > 0 else {
            return nil
        }
        let r = max(0, min(radius, min(width, height) / 2))
        let rounded = roundedRectCornerSet(corners)
        let minX = x
        let minY = y
        let maxX = x + width
        let maxY = y + height
        let topLeft = rounded.contains("1")
        let topRight = rounded.contains("2")
        let bottomRight = rounded.contains("3")
        let bottomLeft = rounded.contains("4")

        var segments = ["M \(svgNumber(minX + (topLeft ? r : 0))) \(svgNumber(minY))"]
        segments.append("L \(svgNumber(maxX - (topRight ? r : 0))) \(svgNumber(minY))")
        if topRight {
            segments.append("Q \(svgNumber(maxX)) \(svgNumber(minY)) \(svgNumber(maxX)) \(svgNumber(minY + r))")
        } else {
            segments.append("L \(svgNumber(maxX)) \(svgNumber(minY))")
        }
        segments.append("L \(svgNumber(maxX)) \(svgNumber(maxY - (bottomRight ? r : 0)))")
        if bottomRight {
            segments.append("Q \(svgNumber(maxX)) \(svgNumber(maxY)) \(svgNumber(maxX - r)) \(svgNumber(maxY))")
        } else {
            segments.append("L \(svgNumber(maxX)) \(svgNumber(maxY))")
        }
        segments.append("L \(svgNumber(minX + (bottomLeft ? r : 0))) \(svgNumber(maxY))")
        if bottomLeft {
            segments.append("Q \(svgNumber(minX)) \(svgNumber(maxY)) \(svgNumber(minX)) \(svgNumber(maxY - r))")
        } else {
            segments.append("L \(svgNumber(minX)) \(svgNumber(maxY))")
        }
        segments.append("L \(svgNumber(minX)) \(svgNumber(minY + (topLeft ? r : 0)))")
        if topLeft {
            segments.append("Q \(svgNumber(minX)) \(svgNumber(minY)) \(svgNumber(minX + r)) \(svgNumber(minY))")
        } else {
            segments.append("L \(svgNumber(minX)) \(svgNumber(minY))")
        }
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

    private func roundedRectCornerSet(_ corners: String?) -> Set<Character> {
        guard let corners, corners.isEmpty == false else {
            return Set("1234")
        }
        return Set(corners.filter { "1234".contains($0) })
    }
}
