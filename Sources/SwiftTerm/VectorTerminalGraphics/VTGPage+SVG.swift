import Foundation

public extension VTGPage {
    /// Export the page as it is displayed — scrolled, clipped to its viewport,
    /// background first, then each visible layer by z — as an SVG fragment to
    /// append after the base scene.
    func makeSVGFragment(canvasWidth: Double, canvasHeight: Double) -> String {
        let viewport = self.viewport ?? VTGLayerClip(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        let originX = viewport.x - scrollX
        let originY = viewport.y - scrollY
        // The part of the page inside the viewport, in canvas coordinates.
        let visibleMinX = max(viewport.x, originX)
        let visibleMinY = max(viewport.y, originY)
        let visibleMaxX = min(viewport.x + viewport.width, originX + width)
        let visibleMaxY = min(viewport.y + viewport.height, originY + height)
        let pageClipID = "vtg-page-\(id)-visible"
        let viewportClipID = "vtg-page-\(id)-viewport"
        var definitions = [
            "<clipPath id=\"\(viewportClipID)\"><rect x=\"\(svgNumber(viewport.x))\" y=\"\(svgNumber(viewport.y))\" width=\"\(svgNumber(viewport.width))\" height=\"\(svgNumber(viewport.height))\"/></clipPath>"
        ]
        var body: [String] = []
        if visibleMaxX > visibleMinX, visibleMaxY > visibleMinY {
            definitions.append("<clipPath id=\"\(pageClipID)\"><rect x=\"\(svgNumber(visibleMinX))\" y=\"\(svgNumber(visibleMinY))\" width=\"\(svgNumber(visibleMaxX - visibleMinX))\" height=\"\(svgNumber(visibleMaxY - visibleMinY))\"/></clipPath>")
            if let background {
                body.append("<rect x=\"\(svgNumber(visibleMinX))\" y=\"\(svgNumber(visibleMinY))\" width=\"\(svgNumber(visibleMaxX - visibleMinX))\" height=\"\(svgNumber(visibleMaxY - visibleMinY))\" fill=\"\(background.svgColor)\" fill-opacity=\"\(svgNumber(background.alpha))\"/>")
            }
        }
        for layer in orderedLayers where layer.isVisible && layer.alpha > 0 {
            let content = layer.scene.makeSVGFragment()
            guard !content.isEmpty else { continue }
            let translateX: Double
            let translateY: Double
            var clip = ""
            switch layer.scrollMode {
            case .page:
                guard visibleMaxX > visibleMinX, visibleMaxY > visibleMinY else { continue }
                translateX = originX + layer.offset.x
                translateY = originY + layer.offset.y
                clip = " clip-path=\"url(#\(pageClipID))\""
            case .fixed:
                translateX = viewport.x + layer.offset.x
                translateY = viewport.y + layer.offset.y
            }
            let opacity = layer.alpha < 1 ? " opacity=\"\(svgNumber(layer.alpha))\"" : ""
            body.append("<g data-vtg-page-layer=\"\(layer.id)\"\(clip)\(opacity)><g transform=\"translate(\(svgNumber(translateX)) \(svgNumber(translateY)))\">\(content)</g></g>")
        }
        let pageOpacity = alpha < 1 ? " opacity=\"\(svgNumber(alpha))\"" : ""
        return "<defs>\(definitions.joined())</defs>\n<g data-vtg-page=\"\(id)\" clip-path=\"url(#\(viewportClipID))\"\(pageOpacity)>\n\(body.joined(separator: "\n"))\n</g>"
    }
}
