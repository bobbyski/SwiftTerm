import Foundation

extension VTGPrimitive {
    /// SVG element for a retained bitmap or vector sprite instance.
    func spriteSVGFragment(
        assetID: String,
        x: Double,
        y: Double,
        rotation: Double,
        scale: Double,
        anchorX: Double,
        anchorY: Double,
        scene: VTGGraphicsScene
    ) -> String {
        if let asset = scene.spriteAsset(id: assetID) {
            let width = asset.width * scale
            let height = asset.height * scale
            let anchorScreenX = x + width * anchorX
            let anchorScreenY = y + height * anchorY
            let mimeType = asset.format.lowercased() == "jpg" ? "image/jpeg" : "image/\(asset.format.lowercased())"
            let rendering = asset.filter == .nearest ? " image-rendering=\"pixelated\"" : ""
            return "<image x=\"\(svgNumber(x))\" y=\"\(svgNumber(y))\" width=\"\(svgNumber(width))\" height=\"\(svgNumber(height))\" href=\"data:\(mimeType);base64,\(asset.base64)\"\(rendering) transform=\"rotate(\(svgNumber(rotation)) \(svgNumber(anchorScreenX)) \(svgNumber(anchorScreenY)))\"/>"
        }

        if let asset = scene.indexedSpriteAsset(id: assetID) {
            return indexedSpriteSVGFragment(
                asset,
                x: x,
                y: y,
                rotation: rotation,
                scale: scale,
                anchorX: anchorX,
                anchorY: anchorY
            )
        }

        guard let asset = scene.vectorSpriteAsset(id: assetID) else {
            return ""
        }
        let anchorScreenX = x + asset.width * scale * anchorX
        let anchorScreenY = y + asset.height * scale * anchorY
        let transform = "translate(\(svgNumber(anchorScreenX)) \(svgNumber(anchorScreenY))) rotate(\(svgNumber(rotation))) scale(\(svgNumber(scale))) translate(\(svgNumber(-asset.width * anchorX)) \(svgNumber(-asset.height * anchorY)))"
        return "<path d=\"\(asset.commands.svgPathData)\"\(svgFill(asset.fill))\(svgStroke(asset.stroke, width: asset.lineWidth)) transform=\"\(transform)\" data-anchor-x=\"\(svgNumber(anchorScreenX))\" data-anchor-y=\"\(svgNumber(anchorScreenY))\"/>"
    }

    private func indexedSpriteSVGFragment(
        _ asset: VTGIndexedSpriteAsset,
        x: Double,
        y: Double,
        rotation: Double,
        scale: Double,
        anchorX: Double,
        anchorY: Double
    ) -> String {
        let anchorScreenX = x + Double(asset.width) * scale * anchorX
        let anchorScreenY = y + Double(asset.height) * scale * anchorY
        let transform = "translate(\(svgNumber(anchorScreenX)) \(svgNumber(anchorScreenY))) rotate(\(svgNumber(rotation))) scale(\(svgNumber(scale))) translate(\(svgNumber(-Double(asset.width) * anchorX)) \(svgNumber(-Double(asset.height) * anchorY)))"
        var rects: [String] = []
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
                let color = asset.palette[paletteIndex]
                rects.append("<rect x=\"\(column)\" y=\"\(row)\" width=\"1\" height=\"1\" fill=\"\(color.svgColor)\" fill-opacity=\"\(svgNumber(color.alpha))\"/>")
            }
        }
        let rendering = asset.filter == .nearest ? " shape-rendering=\"crispEdges\"" : ""
        return "<g transform=\"\(transform)\" data-indexed-sprite=\"\(asset.id)\"\(rendering)>\(rects.joined())</g>"
    }
}
