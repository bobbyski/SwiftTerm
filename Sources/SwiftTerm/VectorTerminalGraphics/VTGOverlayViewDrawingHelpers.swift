#if os(macOS)
import AppKit

extension VTGOverlayView {
    /// Apply a constrained VTG path command list to the current CGContext path.
    func applyPathCommands(_ commands: [VTGPathCommand], in context: CGContext) {
        for command in commands {
            switch command {
            case .move(let point):
                context.move(to: CGPoint(x: point.x, y: point.y))
            case .line(let point):
                context.addLine(to: CGPoint(x: point.x, y: point.y))
            case .quadratic(let control, let end):
                context.addQuadCurve(to: CGPoint(x: end.x, y: end.y), control: CGPoint(x: control.x, y: control.y))
            case .cubic(let control1, let control2, let end):
                context.addCurve(
                    to: CGPoint(x: end.x, y: end.y),
                    control1: CGPoint(x: control1.x, y: control1.y),
                    control2: CGPoint(x: control2.x, y: control2.y)
                )
            case .close:
                context.closePath()
            }
        }
    }

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

    /// Fill and/or stroke the current path without losing one operation to the other.
    func drawCurrentPath(
        stroke: VTGColor?,
        fill: VTGColor?,
        lineWidth: Double,
        lineCap: VTGLineCap? = nil,
        lineJoin: VTGLineJoin? = nil,
        in context: CGContext
    ) {
        if let fill, let stroke {
            context.setFillColor(fill.cgColor)
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(lineWidth)
            if let lineCap {
                context.setLineCap(lineCap.cgLineCap)
            }
            if let lineJoin {
                context.setLineJoin(lineJoin.cgLineJoin)
            }
            context.drawPath(using: .fillStroke)
        } else if let fill {
            context.setFillColor(fill.cgColor)
            context.fillPath()
        } else if let stroke {
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(lineWidth)
            if let lineCap {
                context.setLineCap(lineCap.cgLineCap)
            }
            if let lineJoin {
                context.setLineJoin(lineJoin.cgLineJoin)
            }
            context.strokePath()
        } else {
            context.beginPath()
        }
    }

    /// Shared ellipse/circle drawing with optional stroke and fill.
    func drawEllipse(rect: CGRect, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double, in context: CGContext) {
        if let fill {
            context.setFillColor(fill.cgColor)
            context.fillEllipse(in: rect)
        }
        if let stroke {
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(lineWidth)
            context.strokeEllipse(in: rect)
        }
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

extension VTGLineCap {
    var cgLineCap: CGLineCap {
        switch self {
        case .butt:
            return .butt
        case .round:
            return .round
        case .square:
            return .square
        }
    }
}

extension VTGLineJoin {
    var cgLineJoin: CGLineJoin {
        switch self {
        case .miter:
            return .miter
        case .round:
            return .round
        case .bevel:
            return .bevel
        }
    }
}

extension NSColor {
    /// Convert VTG colors into AppKit colors for text drawing.
    convenience init(_ color: VTGColor) {
        self.init(
            calibratedRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
    }
}

extension VTGColor {
    /// Core Graphics color representation for primitive drawing.
    var cgColor: CGColor {
        CGColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}
#endif
