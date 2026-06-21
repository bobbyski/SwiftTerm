#if os(macOS)
import AppKit

extension VTGOverlayView {
    func drawPixel(x: Double, y: Double, color: VTGColor, in context: CGContext) {
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: x.rounded(.down), y: y.rounded(.down), width: 1, height: 1))
    }

    /// Clear a rectangular region back to transparent pixels in the current
    /// graphics layer. This is intentionally different from drawing a
    /// background-colored rectangle: later primitives can still draw over the
    /// cleared region, and lower layers remain visible through it.
    func drawClearRect(x: Double, y: Double, width: Double, height: Double, in context: CGContext) {
        context.clear(CGRect(x: x, y: y, width: width, height: height))
    }

    func drawLine(
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double,
        stroke: VTGColor,
        width: Double,
        lineCap: VTGLineCap?,
        in context: CGContext
    ) {
        context.setStrokeColor(stroke.cgColor)
        context.setLineWidth(width)
        context.setLineCap(lineCap?.cgLineCap ?? .round)
        context.move(to: CGPoint(x: x1, y: y1))
        context.addLine(to: CGPoint(x: x2, y: y2))
        context.strokePath()
    }

    func drawPolyline(
        points: [VTGPoint],
        stroke: VTGColor,
        width: Double,
        lineCap: VTGLineCap?,
        lineJoin: VTGLineJoin?,
        in context: CGContext
    ) {
        guard let first = points.first else {
            return
        }
        context.setStrokeColor(stroke.cgColor)
        context.setLineWidth(width)
        context.setLineCap(lineCap?.cgLineCap ?? .round)
        context.setLineJoin(lineJoin?.cgLineJoin ?? .round)
        context.move(to: CGPoint(x: first.x, y: first.y))
        for point in points.dropFirst() {
            context.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        context.strokePath()
    }

    func drawCurve(
        _ curve: VTGCurve,
        stroke: VTGColor,
        width: Double,
        lineCap: VTGLineCap?,
        lineJoin: VTGLineJoin?,
        in context: CGContext
    ) {
        context.setStrokeColor(stroke.cgColor)
        context.setLineWidth(width)
        context.setLineCap(lineCap?.cgLineCap ?? .round)
        context.setLineJoin(lineJoin?.cgLineJoin ?? .round)
        switch curve {
        case .quadratic(let start, let control, let end):
            context.move(to: CGPoint(x: start.x, y: start.y))
            context.addQuadCurve(to: CGPoint(x: end.x, y: end.y), control: CGPoint(x: control.x, y: control.y))
        case .cubic(let start, let control1, let control2, let end):
            context.move(to: CGPoint(x: start.x, y: start.y))
            context.addCurve(
                to: CGPoint(x: end.x, y: end.y),
                control1: CGPoint(x: control1.x, y: control1.y),
                control2: CGPoint(x: control2.x, y: control2.y)
            )
        }
        context.strokePath()
    }

    func drawText(x: Double, y: Double, value: String, color: VTGColor, size: Double) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor(color)
        ]
        value.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }

    func drawImage(x: Double, y: Double, width: Double, height: Double, data: Data, filter: VTGSpriteFilter, in context: CGContext) {
        guard let image = NSImage(data: data) else {
            return
        }
        context.saveGState()
        context.interpolationQuality = filter == .nearest ? .none : .high
        image.draw(in: CGRect(x: x, y: y, width: width, height: height))
        context.restoreGState()
    }
}
#endif
