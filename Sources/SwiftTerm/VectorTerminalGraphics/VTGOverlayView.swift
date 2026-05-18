#if os(macOS)
import AppKit

/// Transparent AppKit overlay that renders retained VTG primitives.
public final class VTGOverlayView: NSView {
    /// Current retained VTG scene to draw.
    public var scene: VTGGraphicsScene? {
        didSet {
            needsDisplay = true
        }
    }

    /// Use top-left origin so VTG pixel coordinates match terminal screenshots.
    public override var isFlipped: Bool {
        true
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// Ignore mouse hits so input continues to flow to the terminal view.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// Draw all retained VTG primitives into the current graphics context.
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let scene else {
            return
        }

        context.saveGState()
        for primitive in scene.renderPrimitives {
            let layer = scene.layer(for: primitive)
            let offset = scene.offset(for: layer)
            context.saveGState()
            context.setAlpha(scene.alpha(for: layer))
            if let clip = scene.clip(for: layer) {
                context.clip(to: CGRect(x: clip.x, y: clip.y, width: clip.width, height: clip.height))
            }
            if let viewport = scene.viewportTransform(
                for: layer,
                canvasWidth: bounds.width,
                canvasHeight: bounds.height
            ) {
                context.clip(to: CGRect(x: viewport.x, y: viewport.y, width: viewport.width, height: viewport.height))
                context.translateBy(x: viewport.x, y: viewport.y)
                context.scaleBy(x: viewport.scaleX, y: viewport.scaleY)
            }
            context.translateBy(x: offset.x, y: offset.y)
            draw(primitive, in: context, scene: scene)
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// Draw one primitive using Core Graphics/AppKit.
    private func draw(_ primitive: VTGPrimitive, in context: CGContext, scene: VTGGraphicsScene) {
        switch primitive {
        case .pixel(_, let x, let y, let color):
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: x.rounded(.down), y: y.rounded(.down), width: 1, height: 1))

        case .line(_, let x1, let y1, let x2, let y2, let stroke, let width):
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: x1, y: y1))
            context.addLine(to: CGPoint(x: x2, y: y2))
            context.strokePath()

        case .draw(_, let points, let stroke, let width):
            guard let first = points.first else {
                return
            }
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: first.x, y: first.y))
            for point in points.dropFirst() {
                context.addLine(to: CGPoint(x: point.x, y: point.y))
            }
            context.strokePath()

        case .curve(_, let curve, let stroke, let width):
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
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

        case .triangle(_, let p1, let p2, let p3, let stroke, let fill, let lineWidth):
            context.beginPath()
            context.move(to: CGPoint(x: p1.x, y: p1.y))
            context.addLine(to: CGPoint(x: p2.x, y: p2.y))
            context.addLine(to: CGPoint(x: p3.x, y: p3.y))
            context.closePath()
            drawCurrentPath(stroke: stroke, fill: fill, lineWidth: lineWidth, in: context)

        case .path(_, let commands, let stroke, let fill, let lineWidth):
            context.beginPath()
            applyPathCommands(commands, in: context)
            drawCurrentPath(stroke: stroke, fill: fill, lineWidth: lineWidth, in: context)

        case .rect(_, let x, let y, let width, let height, let radius, let stroke, let fill, let lineWidth):
            let rect = CGRect(x: x, y: y, width: width, height: height)
            let clampedRadius = max(0, min(radius, min(width, height) / 2))
            let path = clampedRadius > 0 ? CGPath(roundedRect: rect, cornerWidth: clampedRadius, cornerHeight: clampedRadius, transform: nil) : nil
            if let fill {
                context.setFillColor(fill.cgColor)
                if let path {
                    context.addPath(path)
                    context.fillPath()
                } else {
                    context.fill(rect)
                }
            }
            if let stroke {
                context.setStrokeColor(stroke.cgColor)
                context.setLineWidth(lineWidth)
                if let path {
                    context.addPath(path)
                    context.strokePath()
                } else {
                    context.stroke(rect)
                }
            }

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
            if let asset = scene.spriteAsset(id: assetID),
               let image = NSImage(data: asset.data) {
                let width = asset.width * scale
                let height = asset.height * scale
                context.saveGState()
                // Sprite transforms deliberately apply only to retained sprite
                // instances. Immediate primitives stay simple and stateless.
                context.translateBy(x: x + width * anchorX, y: y + height * anchorY)
                context.rotate(by: CGFloat(rotation * .pi / 180))
                image.draw(in: CGRect(x: -width * anchorX, y: -height * anchorY, width: width, height: height))
                context.restoreGState()
                return
            }
            guard let asset = scene.vectorSpriteAsset(id: assetID) else {
                return
            }
            let width = asset.width * scale
            let height = asset.height * scale
            context.saveGState()
            context.translateBy(x: x + width * anchorX, y: y + height * anchorY)
            context.rotate(by: CGFloat(rotation * .pi / 180))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -asset.width * anchorX, y: -asset.height * anchorY)
            context.beginPath()
            applyPathCommands(asset.commands, in: context)
            if let fill = asset.fill {
                context.setFillColor(fill.cgColor)
                if let stroke = asset.stroke {
                    context.setStrokeColor(stroke.cgColor)
                    context.setLineWidth(asset.lineWidth)
                    context.drawPath(using: .fillStroke)
                } else {
                    context.fillPath()
                }
            } else if let stroke = asset.stroke {
                context.setStrokeColor(stroke.cgColor)
                context.setLineWidth(asset.lineWidth)
                context.strokePath()
            }
            context.restoreGState()
        }
    }

    /// Apply a constrained VTG path command list to the current CGContext path.
    private func applyPathCommands(_ commands: [VTGPathCommand], in context: CGContext) {
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

    /// Fill and/or stroke the current path without losing one operation to the other.
    private func drawCurrentPath(stroke: VTGColor?, fill: VTGColor?, lineWidth: Double, in context: CGContext) {
        if let fill, let stroke {
            context.setFillColor(fill.cgColor)
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(lineWidth)
            context.drawPath(using: .fillStroke)
        } else if let fill {
            context.setFillColor(fill.cgColor)
            context.fillPath()
        } else if let stroke {
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(lineWidth)
            context.strokePath()
        } else {
            context.beginPath()
        }
    }

    /// Shared ellipse/circle drawing with optional stroke and fill.
    private func drawEllipse(rect: CGRect, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double, in context: CGContext) {
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

private extension NSColor {
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

private extension VTGColor {
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
