#if os(macOS)
import AppKit

extension VTGOverlayView {
    /// Draw a retained rectangle, using the rounded-rect path helper only when
    /// the primitive asks for rounded corners.
    func drawRect(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        radius: Double,
        corners: String?,
        stroke: VTGColor?,
        fill: VTGColor?,
        lineWidth: Double,
        lineJoin: VTGLineJoin?,
        in context: CGContext
    ) {
        let rect = CGRect(x: x, y: y, width: width, height: height)
        let clampedRadius = max(0, min(radius, min(width, height) / 2))
        guard clampedRadius > 0 else {
            if let fill {
                context.setFillColor(fill.cgColor)
                context.fill(rect)
            }
            if let stroke {
                context.setStrokeColor(stroke.cgColor)
                context.setLineWidth(lineWidth)
                if let lineJoin {
                    context.setLineJoin(lineJoin.cgLineJoin)
                }
                context.stroke(rect)
            }
            return
        }
        context.beginPath()
        applyRoundedRectPath(rect: rect, radius: clampedRadius, corners: corners, in: context)
        drawCurrentPath(stroke: stroke, fill: fill, lineWidth: lineWidth, lineJoin: lineJoin, in: context)
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

}
#endif
