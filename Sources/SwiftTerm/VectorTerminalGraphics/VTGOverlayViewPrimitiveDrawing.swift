#if os(macOS)
import AppKit

extension VTGOverlayView {
    /// Draw one retained VTG primitive using Core Graphics/AppKit.
    func drawPrimitive(_ primitive: VTGPrimitive, in context: CGContext, scene: VTGGraphicsScene) {
        switch primitive {
        case .pixel(_, let x, let y, let color):
            drawPixel(x: x, y: y, color: color, in: context)

        case .clearRect(_, let x, let y, let width, let height):
            drawClearRect(x: x, y: y, width: width, height: height, in: context)

        case .line(_, let x1, let y1, let x2, let y2, let stroke, let width, let lineCap):
            drawLine(x1: x1, y1: y1, x2: x2, y2: y2, stroke: stroke, width: width, lineCap: lineCap, in: context)

        case .draw(_, let points, let stroke, let width, let lineCap, let lineJoin):
            drawPolyline(points: points, stroke: stroke, width: width, lineCap: lineCap, lineJoin: lineJoin, in: context)

        case .curve(_, let curve, let stroke, let width, let lineCap, let lineJoin):
            drawCurve(curve, stroke: stroke, width: width, lineCap: lineCap, lineJoin: lineJoin, in: context)

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
            drawText(x: x, y: y, value: value, color: color, size: size)

        case .image(_, let x, let y, let width, let height, _, let data, _, let filter):
            drawImage(x: x, y: y, width: width, height: height, data: data, filter: filter, in: context)

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
