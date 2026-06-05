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
#endif
