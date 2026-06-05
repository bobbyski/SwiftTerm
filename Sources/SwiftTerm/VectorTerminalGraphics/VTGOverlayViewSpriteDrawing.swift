#if os(macOS)
import AppKit

extension VTGOverlayView {
    /// Draw a retained bitmap or vector sprite with sprite-only transforms.
    func drawSprite(
        assetID: String,
        x: Double,
        y: Double,
        rotation: Double,
        scale: Double,
        anchorX: Double,
        anchorY: Double,
        in context: CGContext,
        scene: VTGGraphicsScene
    ) {
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
#endif
