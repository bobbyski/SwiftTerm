#if os(macOS)
import AppKit

extension VTGOverlayView {
    /// Draw one retained VTG primitive using Core Graphics/AppKit.
    func drawPrimitive(_ primitive: VTGPrimitive, in context: CGContext, scene: VTGGraphicsScene) {
        switch primitive {
        case .pixel(_, let x, let y, let color):
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: x.rounded(.down), y: y.rounded(.down), width: 1, height: 1))

        case .line(_, let x1, let y1, let x2, let y2, let stroke, let width, let lineCap):
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(width)
            context.setLineCap(lineCap?.cgLineCap ?? .round)
            context.move(to: CGPoint(x: x1, y: y1))
            context.addLine(to: CGPoint(x: x2, y: y2))
            context.strokePath()

        case .draw(_, let points, let stroke, let width, let lineCap, let lineJoin):
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

        case .curve(_, let curve, let stroke, let width, let lineCap, let lineJoin):
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

        case .triangle(_, let p1, let p2, let p3, let radius, let stroke, let fill, let lineWidth, let lineJoin):
            context.beginPath()
            applyRoundedPolygonPath(points: [p1, p2, p3], radius: radius, in: context)
            drawCurrentPath(stroke: stroke, fill: fill, lineWidth: lineWidth, lineJoin: lineJoin, in: context)

        case .path(_, let commands, let stroke, let fill, let lineWidth, let lineCap, let lineJoin):
            context.beginPath()
            applyPathCommands(commands, in: context)
            drawCurrentPath(stroke: stroke, fill: fill, lineWidth: lineWidth, lineCap: lineCap, lineJoin: lineJoin, in: context)

        case .rect(_, let x, let y, let width, let height, let radius, let corners, let stroke, let fill, let lineWidth, let lineJoin):
            drawRect(
                x: x,
                y: y,
                width: width,
                height: height,
                radius: radius,
                corners: corners,
                stroke: stroke,
                fill: fill,
                lineWidth: lineWidth,
                lineJoin: lineJoin,
                in: context
            )

        case .circle(_, let cx, let cy, let radius, let stroke, let fill, let lineWidth):
            let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            drawEllipse(rect: rect, stroke: stroke, fill: fill, lineWidth: lineWidth, in: context)

        case .ellipse(_, let cx, let cy, let rx, let ry, let stroke, let fill, let lineWidth):
            let rect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
            drawEllipse(rect: rect, stroke: stroke, fill: fill, lineWidth: lineWidth, in: context)

        case .text(_, let x, let y, let value, let color, let size):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: NSColor(color)
            ]
            value.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)

        case .image(_, let x, let y, let width, let height, _, let data, _):
            guard let image = NSImage(data: data) else {
                return
            }
            image.draw(in: CGRect(x: x, y: y, width: width, height: height))

        case .sprite(_, let assetID, let x, let y, let rotation, let scale, let anchorX, let anchorY):
            drawSprite(
                assetID: assetID,
                x: x,
                y: y,
                rotation: rotation,
                scale: scale,
                anchorX: anchorX,
                anchorY: anchorY,
                in: context,
                scene: scene
            )
        }
    }
}
#endif
