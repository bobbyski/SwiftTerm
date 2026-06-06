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
            context.interpolationQuality = asset.filter == .nearest ? .none : .high
            // Sprite transforms deliberately apply only to retained sprite
            // instances. Immediate primitives stay simple and stateless.
            context.translateBy(x: x + width * anchorX, y: y + height * anchorY)
            context.rotate(by: CGFloat(rotation * .pi / 180))
            image.draw(in: CGRect(x: -width * anchorX, y: -height * anchorY, width: width, height: height))
            context.restoreGState()
            return
        }
        if let asset = scene.indexedSpriteAsset(id: assetID) {
            drawIndexedSprite(asset, x: x, y: y, rotation: rotation, scale: scale, anchorX: anchorX, anchorY: anchorY, in: context)
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

    /// Draw a palette-indexed sprite where each source value maps to one
    /// logical pixel before the normal sprite transform is applied.
    func drawIndexedSprite(
        _ asset: VTGIndexedSpriteAsset,
        x: Double,
        y: Double,
        rotation: Double,
        scale: Double,
        anchorX: Double,
        anchorY: Double,
        in context: CGContext
    ) {
        context.saveGState()
        context.translateBy(x: x + Double(asset.width) * scale * anchorX, y: y + Double(asset.height) * scale * anchorY)
        context.rotate(by: CGFloat(rotation * .pi / 180))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -Double(asset.width) * anchorX, y: -Double(asset.height) * anchorY)
        for row in 0..<asset.height {
            for column in 0..<asset.width {
                let index = row * asset.width + column
                let paletteIndex = asset.pixels[index]
                if let transparentIndex = asset.transparentIndex, paletteIndex == transparentIndex {
                    continue
                }
                guard paletteIndex >= 0, paletteIndex < asset.palette.count else {
                    continue
                }
                context.setFillColor(asset.palette[paletteIndex].cgColor)
                context.fill(CGRect(x: column, y: row, width: 1, height: 1))
            }
        }
        context.restoreGState()
    }
}
#endif
