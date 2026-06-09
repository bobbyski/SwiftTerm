#if os(macOS)
import CoreGraphics
import Foundation
import simd

/// Converts the Metal-native VTG primitive subset into the same colored
/// triangle vertices used by the terminal's existing Metal color pipeline.
///
/// This renderer is intentionally narrow: it handles the proven layer `-1`
/// under-text primitives and skips richer features such as complex path
/// tessellation, clipping, text, and textures until those Metal paths are
/// designed deliberately.
struct VTGMetalPrimitiveRenderer {
    /// Vertices that can be drawn under one Metal scissor state.
    struct Batch {
        var clip: VTGLayerClip?
        var vertices: [ColorVertex]
    }

    static func makeVertices(
        plan: VTGRenderPlan,
        scale: CGFloat,
        drawableHeight: CGFloat
    ) -> [ColorVertex] {
        makeBatches(plan: plan, scale: scale, drawableHeight: drawableHeight).flatMap(\.vertices)
    }

    static func makeBatches(
        plan: VTGRenderPlan,
        scale: CGFloat,
        drawableHeight: CGFloat
    ) -> [Batch] {
        var batches: [Batch] = []
        var vertices: [ColorVertex] = []
        var currentClip: VTGLayerClip?

        func flushBatch() {
            guard vertices.isEmpty == false else {
                return
            }
            batches.append(Batch(clip: currentClip, vertices: vertices))
            vertices.removeAll(keepingCapacity: true)
        }

        for entry in plan.entries {
            if entry.clip != currentClip {
                flushBatch()
                currentClip = entry.clip
            }

            let alpha = Float(entry.alpha)
            switch entry.primitive {
            case .pixel(_, let x, let y, let color):
                appendRect(
                    x: x + entry.offset.x,
                    y: y + entry.offset.y,
                    width: 1,
                    height: 1,
                    color: color.metalSIMD(alpha: alpha),
                    scale: scale,
                    drawableHeight: drawableHeight,
                    vertices: &vertices
                )

            case .line(_, let x1, let y1, let x2, let y2, let stroke, let width, _):
                appendLine(
                    from: VTGPoint(x: x1 + entry.offset.x, y: y1 + entry.offset.y),
                    to: VTGPoint(x: x2 + entry.offset.x, y: y2 + entry.offset.y),
                    width: width,
                    color: stroke.metalSIMD(alpha: alpha),
                    scale: scale,
                    drawableHeight: drawableHeight,
                    vertices: &vertices
                )

            case .draw(_, let points, let stroke, let width, _, _):
                guard points.count > 1 else {
                    continue
                }
                for index in 0..<(points.count - 1) {
                    let start = points[index]
                    let end = points[index + 1]
                    appendLine(
                        from: VTGPoint(x: start.x + entry.offset.x, y: start.y + entry.offset.y),
                        to: VTGPoint(x: end.x + entry.offset.x, y: end.y + entry.offset.y),
                        width: width,
                        color: stroke.metalSIMD(alpha: alpha),
                        scale: scale,
                        drawableHeight: drawableHeight,
                        vertices: &vertices
                    )
                }

            case .curve(_, let curve, let stroke, let width, _, _):
                let points = sampledCurvePoints(curve).map { point in
                    VTGPoint(x: point.x + entry.offset.x, y: point.y + entry.offset.y)
                }
                guard points.count > 1 else {
                    continue
                }
                for index in 0..<(points.count - 1) {
                    appendLine(
                        from: points[index],
                        to: points[index + 1],
                        width: width,
                        color: stroke.metalSIMD(alpha: alpha),
                        scale: scale,
                        drawableHeight: drawableHeight,
                        vertices: &vertices
                    )
                }

            case .path(_, let commands, let stroke, let fill, let lineWidth, _, _):
                if let fill {
                    appendPathFill(
                        commands: commands,
                        offset: entry.offset,
                        color: fill.metalSIMD(alpha: alpha),
                        scale: scale,
                        drawableHeight: drawableHeight,
                        vertices: &vertices
                    )
                }
                if let stroke, lineWidth > 0 {
                    appendPathStroke(
                        commands: commands,
                        offset: entry.offset,
                        width: lineWidth,
                        color: stroke.metalSIMD(alpha: alpha),
                        scale: scale,
                        drawableHeight: drawableHeight,
                        vertices: &vertices
                    )
                }

            case .rect(_, let x, let y, let width, let height, let radius, let corners, let stroke, let fill, let lineWidth, _):
                let adjustedX = x + entry.offset.x
                let adjustedY = y + entry.offset.y
                appendRectShape(
                    x: adjustedX,
                    y: adjustedY,
                    width: width,
                    height: height,
                    radius: radius,
                    corners: corners,
                    stroke: stroke?.metalSIMD(alpha: alpha),
                    fill: fill?.metalSIMD(alpha: alpha),
                    lineWidth: lineWidth,
                    scale: scale,
                    drawableHeight: drawableHeight,
                    vertices: &vertices
                )

            case .triangle(_, let p1, let p2, let p3, let radius, let stroke, let fill, let lineWidth, _):
                let points = [
                    VTGPoint(x: p1.x + entry.offset.x, y: p1.y + entry.offset.y),
                    VTGPoint(x: p2.x + entry.offset.x, y: p2.y + entry.offset.y),
                    VTGPoint(x: p3.x + entry.offset.x, y: p3.y + entry.offset.y)
                ]
                appendTriangle(
                    points: points,
                    radius: radius,
                    stroke: stroke?.metalSIMD(alpha: alpha),
                    fill: fill?.metalSIMD(alpha: alpha),
                    lineWidth: lineWidth,
                    scale: scale,
                    drawableHeight: drawableHeight,
                    vertices: &vertices
                )

            case .circle(_, let cx, let cy, let radius, let stroke, let fill, let lineWidth):
                appendEllipse(
                    center: VTGPoint(x: cx + entry.offset.x, y: cy + entry.offset.y),
                    rx: radius,
                    ry: radius,
                    stroke: stroke?.metalSIMD(alpha: alpha),
                    fill: fill?.metalSIMD(alpha: alpha),
                    lineWidth: lineWidth,
                    scale: scale,
                    drawableHeight: drawableHeight,
                    vertices: &vertices
                )

            case .ellipse(_, let cx, let cy, let rx, let ry, let stroke, let fill, let lineWidth):
                appendEllipse(
                    center: VTGPoint(x: cx + entry.offset.x, y: cy + entry.offset.y),
                    rx: rx,
                    ry: ry,
                    stroke: stroke?.metalSIMD(alpha: alpha),
                    fill: fill?.metalSIMD(alpha: alpha),
                    lineWidth: lineWidth,
                    scale: scale,
                    drawableHeight: drawableHeight,
                    vertices: &vertices
                )

            default:
                continue
            }
        }
        flushBatch()
        return batches
    }

    private static func sampledCurvePoints(_ curve: VTGCurve) -> [VTGPoint] {
        let segmentCount = 40
        return (0...segmentCount).map { index in
            let t = Double(index) / Double(segmentCount)
            let inverse = 1 - t
            switch curve {
            case .quadratic(let start, let control, let end):
                return VTGPoint(
                    x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
                    y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
                )
            case .cubic(let start, let control1, let control2, let end):
                return VTGPoint(
                    x: pow(inverse, 3) * start.x + 3 * pow(inverse, 2) * t * control1.x + 3 * inverse * t * t * control2.x + pow(t, 3) * end.x,
                    y: pow(inverse, 3) * start.y + 3 * pow(inverse, 2) * t * control1.y + 3 * inverse * t * t * control2.y + pow(t, 3) * end.y
                )
            }
        }
    }

    private static func appendTriangle(
        points: [VTGPoint],
        radius: Double,
        stroke: SIMD4<Float>?,
        fill: SIMD4<Float>?,
        lineWidth: Double,
        scale: CGFloat,
        drawableHeight: CGFloat,
        vertices: inout [ColorVertex]
    ) {
        guard points.count == 3 else {
            return
        }
        let drawPoints = radius > 0 ? roundedPolygonPoints(points: points, radius: radius) : points
        if let fill {
            appendTriangleFan(points: drawPoints, color: fill, scale: scale, drawableHeight: drawableHeight, vertices: &vertices)
        }
        if let stroke, lineWidth > 0 {
            appendClosedPolyline(points: drawPoints, width: lineWidth, color: stroke, scale: scale, drawableHeight: drawableHeight, vertices: &vertices)
        }
    }

    private static func appendRectShape(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        radius: Double,
        corners: String?,
        stroke: SIMD4<Float>?,
        fill: SIMD4<Float>?,
        lineWidth: Double,
        scale: CGFloat,
        drawableHeight: CGFloat,
        vertices: inout [ColorVertex]
    ) {
        guard width > 0, height > 0 else {
            return
        }
        if radius <= 0 {
            if let fill {
                appendRect(
                    x: x,
                    y: y,
                    width: width,
                    height: height,
                    color: fill,
                    scale: scale,
                    drawableHeight: drawableHeight,
                    vertices: &vertices
                )
            }
            if let stroke, lineWidth > 0 {
                appendClosedPolyline(
                    points: [
                        VTGPoint(x: x, y: y),
                        VTGPoint(x: x + width, y: y),
                        VTGPoint(x: x + width, y: y + height),
                        VTGPoint(x: x, y: y + height)
                    ],
                    width: lineWidth,
                    color: stroke,
                    scale: scale,
                    drawableHeight: drawableHeight,
                    vertices: &vertices
                )
            }
            return
        }

        let points = roundedRectPoints(x: x, y: y, width: width, height: height, radius: radius, corners: corners)
        if let fill {
            appendTriangleFan(points: points, color: fill, scale: scale, drawableHeight: drawableHeight, vertices: &vertices)
        }
        if let stroke, lineWidth > 0 {
            appendClosedPolyline(points: points, width: lineWidth, color: stroke, scale: scale, drawableHeight: drawableHeight, vertices: &vertices)
        }
    }

    private static func appendEllipse(
        center: VTGPoint,
        rx: Double,
        ry: Double,
        stroke: SIMD4<Float>?,
        fill: SIMD4<Float>?,
        lineWidth: Double,
        scale: CGFloat,
        drawableHeight: CGFloat,
        vertices: inout [ColorVertex]
    ) {
        guard rx > 0, ry > 0 else {
            return
        }
        let segmentCount = 48
        let points = (0..<segmentCount).map { index in
            let angle = (Double(index) / Double(segmentCount)) * Double.pi * 2
            return VTGPoint(x: center.x + cos(angle) * rx, y: center.y + sin(angle) * ry)
        }
        if let fill {
            appendTriangleFan(points: [center] + points, color: fill, scale: scale, drawableHeight: drawableHeight, vertices: &vertices)
        }
        if let stroke, lineWidth > 0 {
            appendClosedPolyline(points: points, width: lineWidth, color: stroke, scale: scale, drawableHeight: drawableHeight, vertices: &vertices)
        }
    }

    private static func appendPathFill(
        commands: [VTGPathCommand],
        offset: VTGLayerOffset,
        color: SIMD4<Float>,
        scale: CGFloat,
        drawableHeight: CGFloat,
        vertices: inout [ColorVertex]
    ) {
        // This covers the simple closed polygons and curved shapes VTG demos
        // currently emit. Holes and self-intersections are left for a future
        // real tessellator.
        for subpath in flattenedPathSubpaths(commands) {
            guard subpath.count >= 3 else {
                continue
            }
            let shifted = subpath.map { point in
                VTGPoint(x: point.x + offset.x, y: point.y + offset.y)
            }
            appendTriangleFan(points: shifted, color: color, scale: scale, drawableHeight: drawableHeight, vertices: &vertices)
        }
    }

    private static func appendPathStroke(
        commands: [VTGPathCommand],
        offset: VTGLayerOffset,
        width: Double,
        color: SIMD4<Float>,
        scale: CGFloat,
        drawableHeight: CGFloat,
        vertices: inout [ColorVertex]
    ) {
        var current: VTGPoint?
        var subpathStart: VTGPoint?

        func shifted(_ point: VTGPoint) -> VTGPoint {
            VTGPoint(x: point.x + offset.x, y: point.y + offset.y)
        }

        func appendSegment(from start: VTGPoint, to end: VTGPoint) {
            appendLine(
                from: shifted(start),
                to: shifted(end),
                width: width,
                color: color,
                scale: scale,
                drawableHeight: drawableHeight,
                vertices: &vertices
            )
        }

        func appendSampledCurve(_ curve: VTGCurve) {
            let points = sampledCurvePoints(curve)
            guard points.count > 1 else {
                return
            }
            for index in 0..<(points.count - 1) {
                appendSegment(from: points[index], to: points[index + 1])
            }
        }

        for command in commands {
            switch command {
            case .move(let point):
                current = point
                subpathStart = point

            case .line(let point):
                if let start = current {
                    appendSegment(from: start, to: point)
                }
                current = point

            case .quadratic(let control, let end):
                if let start = current {
                    appendSampledCurve(.quadratic(start: start, control: control, end: end))
                }
                current = end

            case .cubic(let control1, let control2, let end):
                if let start = current {
                    appendSampledCurve(.cubic(start: start, control1: control1, control2: control2, end: end))
                }
                current = end

            case .close:
                if let start = current, let end = subpathStart {
                    appendSegment(from: start, to: end)
                    current = end
                }
            }
        }
    }

    private static func flattenedPathSubpaths(_ commands: [VTGPathCommand]) -> [[VTGPoint]] {
        var subpaths: [[VTGPoint]] = []
        var currentSubpath: [VTGPoint] = []
        var current: VTGPoint?
        var subpathStart: VTGPoint?

        func finishSubpath() {
            if currentSubpath.count >= 3 {
                subpaths.append(currentSubpath)
            }
            currentSubpath.removeAll(keepingCapacity: true)
        }

        func appendCurve(_ curve: VTGCurve) {
            let points = sampledCurvePoints(curve)
            guard points.count > 1 else {
                return
            }
            currentSubpath.append(contentsOf: points.dropFirst())
        }

        for command in commands {
            switch command {
            case .move(let point):
                finishSubpath()
                currentSubpath = [point]
                current = point
                subpathStart = point

            case .line(let point):
                if current != nil {
                    currentSubpath.append(point)
                }
                current = point

            case .quadratic(let control, let end):
                if let start = current {
                    appendCurve(.quadratic(start: start, control: control, end: end))
                }
                current = end

            case .cubic(let control1, let control2, let end):
                if let start = current {
                    appendCurve(.cubic(start: start, control1: control1, control2: control2, end: end))
                }
                current = end

            case .close:
                if let start = subpathStart, currentSubpath.last != start {
                    currentSubpath.append(start)
                }
                finishSubpath()
                current = subpathStart
            }
        }
        finishSubpath()
        return subpaths
    }

    private static func roundedRectPoints(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        radius: Double,
        corners: String?
    ) -> [VTGPoint] {
        let clampedRadius = min(max(0, radius), width / 2, height / 2)
        guard clampedRadius > 0 else {
            return [
                VTGPoint(x: x, y: y),
                VTGPoint(x: x + width, y: y),
                VTGPoint(x: x + width, y: y + height),
                VTGPoint(x: x, y: y + height)
            ]
        }

        let rounded = roundedRectCornerSet(corners)
        let topLeft = rounded.contains("1")
        let topRight = rounded.contains("2")
        let bottomRight = rounded.contains("3")
        let bottomLeft = rounded.contains("4")
        let segments = 8
        var points: [VTGPoint] = []

        func append(_ point: VTGPoint) {
            if points.last != point {
                points.append(point)
            }
        }

        func appendArc(center: VTGPoint, startAngle: Double, endAngle: Double) {
            for step in 1...segments {
                let t = Double(step) / Double(segments)
                let angle = startAngle + (endAngle - startAngle) * t
                append(VTGPoint(
                    x: center.x + cos(angle) * clampedRadius,
                    y: center.y + sin(angle) * clampedRadius
                ))
            }
        }

        append(VTGPoint(x: x + (topLeft ? clampedRadius : 0), y: y))
        append(VTGPoint(x: x + width - (topRight ? clampedRadius : 0), y: y))
        if topRight {
            appendArc(center: VTGPoint(x: x + width - clampedRadius, y: y + clampedRadius), startAngle: -.pi / 2, endAngle: 0)
        } else {
            append(VTGPoint(x: x + width, y: y))
        }

        append(VTGPoint(x: x + width, y: y + height - (bottomRight ? clampedRadius : 0)))
        if bottomRight {
            appendArc(center: VTGPoint(x: x + width - clampedRadius, y: y + height - clampedRadius), startAngle: 0, endAngle: .pi / 2)
        } else {
            append(VTGPoint(x: x + width, y: y + height))
        }

        append(VTGPoint(x: x + (bottomLeft ? clampedRadius : 0), y: y + height))
        if bottomLeft {
            appendArc(center: VTGPoint(x: x + clampedRadius, y: y + height - clampedRadius), startAngle: .pi / 2, endAngle: .pi)
        } else {
            append(VTGPoint(x: x, y: y + height))
        }

        append(VTGPoint(x: x, y: y + (topLeft ? clampedRadius : 0)))
        if topLeft {
            appendArc(center: VTGPoint(x: x + clampedRadius, y: y + clampedRadius), startAngle: .pi, endAngle: .pi * 1.5)
        } else {
            append(VTGPoint(x: x, y: y))
        }

        return points
    }

    private static func roundedRectCornerSet(_ corners: String?) -> Set<Character> {
        guard let corners, corners.isEmpty == false else {
            return Set("1234")
        }
        return Set(corners.filter { "1234".contains($0) })
    }

    private static func roundedPolygonPoints(points: [VTGPoint], radius: Double) -> [VTGPoint] {
        let clampedRadius = max(0, radius)
        guard points.count >= 3, clampedRadius > 0 else {
            return points
        }

        let segments = 8
        var result: [VTGPoint] = []
        for index in points.indices {
            let previous = points[(index + points.count - 1) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let previousDistance = distance(from: current, to: previous)
            let nextDistance = distance(from: current, to: next)
            let cornerRadius = min(clampedRadius, previousDistance / 2, nextDistance / 2)
            guard cornerRadius > 0 else {
                result.append(current)
                continue
            }

            let start = point(from: current, toward: previous, distance: cornerRadius)
            let end = point(from: current, toward: next, distance: cornerRadius)
            if result.last != start {
                result.append(start)
            }
            for step in 1...segments {
                let t = Double(step) / Double(segments)
                result.append(quadraticPoint(start: start, control: current, end: end, t: t))
            }
        }
        return result
    }

    private static func distance(from start: VTGPoint, to end: VTGPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return sqrt(dx * dx + dy * dy)
    }

    private static func point(from start: VTGPoint, toward end: VTGPoint, distance: Double) -> VTGPoint {
        let total = Self.distance(from: start, to: end)
        guard total > 0 else {
            return start
        }
        let scale = distance / total
        return VTGPoint(
            x: start.x + (end.x - start.x) * scale,
            y: start.y + (end.y - start.y) * scale
        )
    }

    private static func quadraticPoint(start: VTGPoint, control: VTGPoint, end: VTGPoint, t: Double) -> VTGPoint {
        let inverse = 1 - t
        return VTGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }

    private static func appendTriangleFan(
        points: [VTGPoint],
        color: SIMD4<Float>,
        scale: CGFloat,
        drawableHeight: CGFloat,
        vertices: inout [ColorVertex]
    ) {
        guard points.count >= 3 else {
            return
        }
        let converted = points.map { point in
            metalPoint(point, scale: scale, drawableHeight: drawableHeight)
        }
        for index in 1..<(converted.count - 1) {
            vertices.append(contentsOf: [
                ColorVertex(position: converted[0], color: color),
                ColorVertex(position: converted[index], color: color),
                ColorVertex(position: converted[index + 1], color: color)
            ])
        }
    }

    private static func appendClosedPolyline(
        points: [VTGPoint],
        width: Double,
        color: SIMD4<Float>,
        scale: CGFloat,
        drawableHeight: CGFloat,
        vertices: inout [ColorVertex]
    ) {
        guard points.count > 1 else {
            return
        }
        for index in 0..<points.count {
            appendLine(
                from: points[index],
                to: points[(index + 1) % points.count],
                width: width,
                color: color,
                scale: scale,
                drawableHeight: drawableHeight,
                vertices: &vertices
            )
        }
    }

    private static func appendRect(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        color: SIMD4<Float>,
        scale: CGFloat,
        drawableHeight: CGFloat,
        vertices: inout [ColorVertex]
    ) {
        guard width > 0, height > 0 else {
            return
        }
        appendQuad(
            points: [
                VTGPoint(x: x, y: y),
                VTGPoint(x: x + width, y: y),
                VTGPoint(x: x, y: y + height),
                VTGPoint(x: x + width, y: y + height)
            ],
            color: color,
            scale: scale,
            drawableHeight: drawableHeight,
            vertices: &vertices
        )
    }

    private static func appendLine(
        from start: VTGPoint,
        to end: VTGPoint,
        width: Double,
        color: SIMD4<Float>,
        scale: CGFloat,
        drawableHeight: CGFloat,
        vertices: inout [ColorVertex]
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0, width > 0 else {
            return
        }
        let half = width / 2
        let nx = -dy / length * half
        let ny = dx / length * half
        appendQuad(
            points: [
                VTGPoint(x: start.x + nx, y: start.y + ny),
                VTGPoint(x: end.x + nx, y: end.y + ny),
                VTGPoint(x: start.x - nx, y: start.y - ny),
                VTGPoint(x: end.x - nx, y: end.y - ny)
            ],
            color: color,
            scale: scale,
            drawableHeight: drawableHeight,
            vertices: &vertices
        )
    }

    private static func appendQuad(
        points: [VTGPoint],
        color: SIMD4<Float>,
        scale: CGFloat,
        drawableHeight: CGFloat,
        vertices: inout [ColorVertex]
    ) {
        guard points.count == 4 else {
            return
        }
        let converted = points.map { point in
            metalPoint(point, scale: scale, drawableHeight: drawableHeight)
        }
        vertices.append(contentsOf: [
            ColorVertex(position: converted[0], color: color),
            ColorVertex(position: converted[1], color: color),
            ColorVertex(position: converted[2], color: color),
            ColorVertex(position: converted[1], color: color),
            ColorVertex(position: converted[3], color: color),
            ColorVertex(position: converted[2], color: color)
        ])
    }

    private static func metalPoint(_ point: VTGPoint, scale: CGFloat, drawableHeight: CGFloat) -> SIMD2<Float> {
        SIMD2<Float>(
            Float(CGFloat(point.x) * scale),
            Float(drawableHeight - (CGFloat(point.y) * scale))
        )
    }
}

private extension VTGColor {
    func metalSIMD(alpha layerAlpha: Float) -> SIMD4<Float> {
        SIMD4<Float>(
            Float(red),
            Float(green),
            Float(blue),
            Float(alpha) * layerAlpha
        )
    }
}
#endif
