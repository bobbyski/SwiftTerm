import Foundation

public extension VTGGraphicsScene {
    /// Export retained VTG primitives as an SVG fragment.
    ///
    /// The fragment intentionally omits the root `<svg>` element so callers can
    /// append it to SwiftTerm's terminal snapshot export or embed it in another
    /// SVG document.
    func makeSVGFragment() -> String {
        makeSVGFragment(canvasWidth: nil, canvasHeight: nil)
    }

    /// Export retained VTG primitives as an SVG fragment for a known canvas.
    ///
    /// Passing the canvas size lets the debug SVG export mirror live rendering
    /// for fixed-resolution viewport layers. The no-argument overload preserves
    /// the historical export behavior for callers that only need raw primitive
    /// coordinates.
    func makeSVGFragment(canvasWidth: Double?, canvasHeight: Double?) -> String {
        var definitions: [String] = []
        let body = renderPrimitives.enumerated().map { index, primitive in
            let layer = layer(for: primitive)
            let offset = offset(for: layer)
            let alpha = alpha(for: layer)
            var fragment = primitive.svgFragment(scene: self)
            guard fragment.isEmpty == false else {
                return fragment
            }
            if offset != .zero {
                fragment = "<g transform=\"translate(\(svgNumber(offset.x)) \(svgNumber(offset.y)))\">\(fragment)</g>"
            }
            if let canvasWidth,
               let canvasHeight,
               let viewport = viewportTransform(for: layer, canvasWidth: canvasWidth, canvasHeight: canvasHeight) {
                let clipID = "vtg-layer-\(layer)-viewport-\(index)"
                definitions.append("<clipPath id=\"\(clipID)\"><rect x=\"\(svgNumber(viewport.x))\" y=\"\(svgNumber(viewport.y))\" width=\"\(svgNumber(viewport.width))\" height=\"\(svgNumber(viewport.height))\"/></clipPath>")
                let transform = "translate(\(svgNumber(viewport.x)) \(svgNumber(viewport.y))) scale(\(svgNumber(viewport.scaleX)) \(svgNumber(viewport.scaleY)))"
                fragment = "<g clip-path=\"url(#\(clipID))\"><g transform=\"\(transform)\">\(fragment)</g></g>"
            }
            if let clip = clip(for: layer) {
                let clipID = "vtg-layer-\(layer)-clip-\(index)"
                definitions.append("<clipPath id=\"\(clipID)\"><rect x=\"\(svgNumber(clip.x))\" y=\"\(svgNumber(clip.y))\" width=\"\(svgNumber(clip.width))\" height=\"\(svgNumber(clip.height))\"/></clipPath>")
                fragment = "<g clip-path=\"url(#\(clipID))\">\(fragment)</g>"
            }
            if alpha < 0.999 {
                fragment = "<g opacity=\"\(svgNumber(alpha))\">\(fragment)</g>"
            }
            return fragment
        }
        let defs = definitions.isEmpty ? "" : "<defs>\n\(definitions.joined(separator: "\n"))\n</defs>\n"
        return defs + body.joined(separator: "\n")
    }
}

private extension VTGPrimitive {
    /// SVG element for one VTG primitive.
    func svgFragment(scene: VTGGraphicsScene) -> String {
        switch self {
        case .pixel(_, let x, let y, let color):
            return "<rect x=\"\(svgNumber(x.rounded(.down)))\" y=\"\(svgNumber(y.rounded(.down)))\" width=\"1\" height=\"1\" fill=\"\(color.svgColor)\" fill-opacity=\"\(svgNumber(color.alpha))\"/>"

        case .line(_, let x1, let y1, let x2, let y2, let stroke, let width, let lineCap):
            return "<line x1=\"\(svgNumber(x1))\" y1=\"\(svgNumber(y1))\" x2=\"\(svgNumber(x2))\" y2=\"\(svgNumber(y2))\" stroke=\"\(stroke.svgColor)\" stroke-opacity=\"\(svgNumber(stroke.alpha))\" stroke-width=\"\(svgNumber(width))\" stroke-linecap=\"\(lineCap?.rawValue ?? "round")\"/>"

        case .draw(_, let points, let stroke, let width, let lineCap, let lineJoin):
            let coordinates = points.map { "\(svgNumber($0.x)),\(svgNumber($0.y))" }.joined(separator: " ")
            return "<polyline points=\"\(coordinates)\" fill=\"none\" stroke=\"\(stroke.svgColor)\" stroke-opacity=\"\(svgNumber(stroke.alpha))\" stroke-width=\"\(svgNumber(width))\" stroke-linecap=\"\(lineCap?.rawValue ?? "round")\" stroke-linejoin=\"\(lineJoin?.rawValue ?? "round")\"/>"

        case .curve(_, let curve, let stroke, let width, let lineCap, let lineJoin):
            return "<path d=\"\(curve.svgPathData)\" fill=\"none\" stroke=\"\(stroke.svgColor)\" stroke-opacity=\"\(svgNumber(stroke.alpha))\" stroke-width=\"\(svgNumber(width))\" stroke-linecap=\"\(lineCap?.rawValue ?? "round")\" stroke-linejoin=\"\(lineJoin?.rawValue ?? "round")\"/>"

        case .triangle(_, let p1, let p2, let p3, let radius, let stroke, let fill, let lineWidth, let lineJoin):
            let points = [p1, p2, p3]
            if radius > 0, let pathData = roundedPolygonPathData(points: points, radius: radius) {
                return "<path d=\"\(pathData)\"\(svgFill(fill))\(svgStroke(stroke, width: lineWidth, lineJoin: lineJoin))/>"
            }
            let pointList = points.map { "\(svgNumber($0.x)),\(svgNumber($0.y))" }.joined(separator: " ")
            return "<polygon points=\"\(pointList)\"\(svgFill(fill))\(svgStroke(stroke, width: lineWidth, lineJoin: lineJoin))/>"

        case .path(_, let commands, let stroke, let fill, let lineWidth, let lineCap, let lineJoin):
            return "<path d=\"\(commands.svgPathData)\"\(svgFill(fill))\(svgStroke(stroke, width: lineWidth, lineCap: lineCap, lineJoin: lineJoin))/>"

        case .rect(_, let x, let y, let width, let height, let radius, let stroke, let fill, let lineWidth, let lineJoin):
            let clampedRadius = max(0, min(radius, min(width, height) / 2))
            let radiusAttributes = clampedRadius > 0 ? " rx=\"\(svgNumber(clampedRadius))\" ry=\"\(svgNumber(clampedRadius))\"" : ""
            return "<rect x=\"\(svgNumber(x))\" y=\"\(svgNumber(y))\" width=\"\(svgNumber(width))\" height=\"\(svgNumber(height))\"\(radiusAttributes)\(svgFill(fill))\(svgStroke(stroke, width: lineWidth, lineJoin: lineJoin))/>"

        case .circle(_, let cx, let cy, let radius, let stroke, let fill, let lineWidth):
            return "<circle cx=\"\(svgNumber(cx))\" cy=\"\(svgNumber(cy))\" r=\"\(svgNumber(radius))\"\(svgFill(fill))\(svgStroke(stroke, width: lineWidth))/>"

        case .ellipse(_, let cx, let cy, let rx, let ry, let stroke, let fill, let lineWidth):
            return "<ellipse cx=\"\(svgNumber(cx))\" cy=\"\(svgNumber(cy))\" rx=\"\(svgNumber(rx))\" ry=\"\(svgNumber(ry))\"\(svgFill(fill))\(svgStroke(stroke, width: lineWidth))/>"

        case .text(_, let x, let y, let value, let color, let size):
            return "<text x=\"\(svgNumber(x))\" y=\"\(svgNumber(y + size))\" fill=\"\(color.svgColor)\" fill-opacity=\"\(svgNumber(color.alpha))\" font-family=\"system-ui, sans-serif\" font-size=\"\(svgNumber(size))\">\(svgEscapedText(value))</text>"

        case .image(_, let x, let y, let width, let height, let format, _, let base64):
            let mimeType = format.lowercased() == "jpg" ? "image/jpeg" : "image/\(format.lowercased())"
            return "<image x=\"\(svgNumber(x))\" y=\"\(svgNumber(y))\" width=\"\(svgNumber(width))\" height=\"\(svgNumber(height))\" href=\"data:\(mimeType);base64,\(base64)\"/>"

        case .sprite(_, let assetID, let x, let y, let rotation, let scale, let anchorX, let anchorY):
            if let asset = scene.spriteAsset(id: assetID) {
                let width = asset.width * scale
                let height = asset.height * scale
                let anchorScreenX = x + width * anchorX
                let anchorScreenY = y + height * anchorY
                let mimeType = asset.format.lowercased() == "jpg" ? "image/jpeg" : "image/\(asset.format.lowercased())"
                return "<image x=\"\(svgNumber(x))\" y=\"\(svgNumber(y))\" width=\"\(svgNumber(width))\" height=\"\(svgNumber(height))\" href=\"data:\(mimeType);base64,\(asset.base64)\" transform=\"rotate(\(svgNumber(rotation)) \(svgNumber(anchorScreenX)) \(svgNumber(anchorScreenY)))\"/>"
            }
            guard let asset = scene.vectorSpriteAsset(id: assetID) else {
                return ""
            }
            let anchorScreenX = x + asset.width * scale * anchorX
            let anchorScreenY = y + asset.height * scale * anchorY
            let transform = "translate(\(svgNumber(anchorScreenX)) \(svgNumber(anchorScreenY))) rotate(\(svgNumber(rotation))) scale(\(svgNumber(scale))) translate(\(svgNumber(-asset.width * anchorX)) \(svgNumber(-asset.height * anchorY)))"
            return "<path d=\"\(asset.commands.svgPathData)\"\(svgFill(asset.fill))\(svgStroke(asset.stroke, width: asset.lineWidth)) transform=\"\(transform)\" data-anchor-x=\"\(svgNumber(anchorScreenX))\" data-anchor-y=\"\(svgNumber(anchorScreenY))\"/>"
        }
    }
}
