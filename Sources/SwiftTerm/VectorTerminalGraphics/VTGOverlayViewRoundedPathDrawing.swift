#if os(macOS)
import AppKit

extension VTGOverlayView {
    /// Apply a polygon path, optionally rounding each corner with a quadratic
    /// curve through the original vertex. The trim radius is clamped per corner
    /// so very small triangles remain valid instead of self-intersecting.
    func applyRoundedPolygonPath(points: [VTGPoint], radius: Double, in context: CGContext) {
        guard points.count >= 3 else {
            return
        }
        let clampedRadius = max(0, radius)
        guard clampedRadius > 0 else {
            context.move(to: CGPoint(x: points[0].x, y: points[0].y))
            for point in points.dropFirst() {
                context.addLine(to: CGPoint(x: point.x, y: point.y))
            }
            context.closePath()
            return
        }

        var corners: [(vertex: VTGPoint, start: VTGPoint, end: VTGPoint)] = []
        for index in points.indices {
            let previous = points[(index - 1 + points.count) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let previousDistance = distance(from: current, to: previous)
            let nextDistance = distance(from: current, to: next)
            guard previousDistance > 0, nextDistance > 0 else {
                continue
            }
            let cornerRadius = min(clampedRadius, previousDistance / 2, nextDistance / 2)
            corners.append((
                vertex: current,
                start: point(from: current, toward: previous, distance: cornerRadius),
                end: point(from: current, toward: next, distance: cornerRadius)
            ))
        }

        guard corners.count == points.count else {
            context.move(to: CGPoint(x: points[0].x, y: points[0].y))
            for point in points.dropFirst() {
                context.addLine(to: CGPoint(x: point.x, y: point.y))
            }
            context.closePath()
            return
        }

        context.move(to: CGPoint(x: corners[0].end.x, y: corners[0].end.y))
        for corner in corners.dropFirst() {
            context.addLine(to: CGPoint(x: corner.start.x, y: corner.start.y))
            context.addQuadCurve(
                to: CGPoint(x: corner.end.x, y: corner.end.y),
                control: CGPoint(x: corner.vertex.x, y: corner.vertex.y)
            )
        }
        context.addLine(to: CGPoint(x: corners[0].start.x, y: corners[0].start.y))
        context.addQuadCurve(
            to: CGPoint(x: corners[0].end.x, y: corners[0].end.y),
            control: CGPoint(x: corners[0].vertex.x, y: corners[0].vertex.y)
        )
        context.closePath()
    }

    /// Apply a rectangle path with optional per-corner rounding.
    ///
    /// `corners` uses the VTG rectangle numbering: 1 is top-left, 2 is
    /// top-right, 3 is bottom-right, and 4 is bottom-left. A missing selector
    /// preserves the original VTG behavior and rounds every corner.
    func applyRoundedRectPath(rect: CGRect, radius: Double, corners: String?, in context: CGContext) {
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        let rounded = roundedRectCornerSet(corners)
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY
        let topLeft = rounded.contains("1")
        let topRight = rounded.contains("2")
        let bottomRight = rounded.contains("3")
        let bottomLeft = rounded.contains("4")

        context.move(to: CGPoint(x: minX + (topLeft ? r : 0), y: minY))
        context.addLine(to: CGPoint(x: maxX - (topRight ? r : 0), y: minY))
        if topRight {
            context.addQuadCurve(to: CGPoint(x: maxX, y: minY + r), control: CGPoint(x: maxX, y: minY))
        } else {
            context.addLine(to: CGPoint(x: maxX, y: minY))
        }
        context.addLine(to: CGPoint(x: maxX, y: maxY - (bottomRight ? r : 0)))
        if bottomRight {
            context.addQuadCurve(to: CGPoint(x: maxX - r, y: maxY), control: CGPoint(x: maxX, y: maxY))
        } else {
            context.addLine(to: CGPoint(x: maxX, y: maxY))
        }
        context.addLine(to: CGPoint(x: minX + (bottomLeft ? r : 0), y: maxY))
        if bottomLeft {
            context.addQuadCurve(to: CGPoint(x: minX, y: maxY - r), control: CGPoint(x: minX, y: maxY))
        } else {
            context.addLine(to: CGPoint(x: minX, y: maxY))
        }
        context.addLine(to: CGPoint(x: minX, y: minY + (topLeft ? r : 0)))
        if topLeft {
            context.addQuadCurve(to: CGPoint(x: minX + r, y: minY), control: CGPoint(x: minX, y: minY))
        } else {
            context.addLine(to: CGPoint(x: minX, y: minY))
        }
        context.closePath()
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
#endif
