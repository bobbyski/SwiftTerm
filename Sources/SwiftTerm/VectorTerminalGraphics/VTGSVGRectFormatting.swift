import Foundation

extension VTGPrimitive {
    /// SVG path data for a rectangle with VTG's optional per-corner rounding.
    ///
    /// Corner selector digits match the live renderer: 1 top-left, 2
    /// top-right, 3 bottom-right, and 4 bottom-left.
    func roundedRectPathData(x: Double, y: Double, width: Double, height: Double, radius: Double, corners: String?) -> String? {
        guard width > 0, height > 0 else {
            return nil
        }
        let r = max(0, min(radius, min(width, height) / 2))
        let rounded = roundedRectCornerSet(corners)
        let minX = x
        let minY = y
        let maxX = x + width
        let maxY = y + height
        let topLeft = rounded.contains("1")
        let topRight = rounded.contains("2")
        let bottomRight = rounded.contains("3")
        let bottomLeft = rounded.contains("4")

        var segments = ["M \(svgNumber(minX + (topLeft ? r : 0))) \(svgNumber(minY))"]
        segments.append("L \(svgNumber(maxX - (topRight ? r : 0))) \(svgNumber(minY))")
        if topRight {
            segments.append("Q \(svgNumber(maxX)) \(svgNumber(minY)) \(svgNumber(maxX)) \(svgNumber(minY + r))")
        } else {
            segments.append("L \(svgNumber(maxX)) \(svgNumber(minY))")
        }
        segments.append("L \(svgNumber(maxX)) \(svgNumber(maxY - (bottomRight ? r : 0)))")
        if bottomRight {
            segments.append("Q \(svgNumber(maxX)) \(svgNumber(maxY)) \(svgNumber(maxX - r)) \(svgNumber(maxY))")
        } else {
            segments.append("L \(svgNumber(maxX)) \(svgNumber(maxY))")
        }
        segments.append("L \(svgNumber(minX + (bottomLeft ? r : 0))) \(svgNumber(maxY))")
        if bottomLeft {
            segments.append("Q \(svgNumber(minX)) \(svgNumber(maxY)) \(svgNumber(minX)) \(svgNumber(maxY - r))")
        } else {
            segments.append("L \(svgNumber(minX)) \(svgNumber(maxY))")
        }
        segments.append("L \(svgNumber(minX)) \(svgNumber(minY + (topLeft ? r : 0)))")
        if topLeft {
            segments.append("Q \(svgNumber(minX)) \(svgNumber(minY)) \(svgNumber(minX + r)) \(svgNumber(minY))")
        } else {
            segments.append("L \(svgNumber(minX)) \(svgNumber(minY))")
        }
        segments.append("Z")
        return segments.joined(separator: " ")
    }

    private func roundedRectCornerSet(_ corners: String?) -> Set<Character> {
        guard let corners, corners.isEmpty == false else {
            return Set("1234")
        }
        return Set(corners.filter { "1234".contains($0) })
    }
}
