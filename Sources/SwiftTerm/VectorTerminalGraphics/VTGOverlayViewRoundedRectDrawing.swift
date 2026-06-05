#if os(macOS)
import AppKit

extension VTGOverlayView {
    /// Apply a rectangle path with optional per-corner rounding.
    ///
    /// `corners` uses the VTG rectangle numbering: 1 is top-left, 2 is
    /// top-right, 3 is bottom-right, and 4 is bottom-left. A missing selector
    /// preserves the original VTG behavior and rounds every corner.
    func applyRoundedRectPath(rect: CGRect, radius: Double, corners: String?, in context: CGContext) {
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        let rounded = roundedRectCornerSet(corners)
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY
        let topLeft = rounded.contains("1")
        let topRight = rounded.contains("2")
        let bottomRight = rounded.contains("3")
        let bottomLeft = rounded.contains("4")

        context.move(to: CGPoint(x: minX + (topLeft ? r : 0), y: minY))
        context.addLine(to: CGPoint(x: maxX - (topRight ? r : 0), y: minY))
        if topRight {
            context.addQuadCurve(to: CGPoint(x: maxX, y: minY + r), control: CGPoint(x: maxX, y: minY))
        } else {
            context.addLine(to: CGPoint(x: maxX, y: minY))
        }
        context.addLine(to: CGPoint(x: maxX, y: maxY - (bottomRight ? r : 0)))
        if bottomRight {
            context.addQuadCurve(to: CGPoint(x: maxX - r, y: maxY), control: CGPoint(x: maxX, y: maxY))
        } else {
            context.addLine(to: CGPoint(x: maxX, y: maxY))
        }
        context.addLine(to: CGPoint(x: minX + (bottomLeft ? r : 0), y: maxY))
        if bottomLeft {
            context.addQuadCurve(to: CGPoint(x: minX, y: maxY - r), control: CGPoint(x: minX, y: maxY))
        } else {
            context.addLine(to: CGPoint(x: minX, y: maxY))
        }
        context.addLine(to: CGPoint(x: minX, y: minY + (topLeft ? r : 0)))
        if topLeft {
            context.addQuadCurve(to: CGPoint(x: minX + r, y: minY), control: CGPoint(x: minX, y: minY))
        } else {
            context.addLine(to: CGPoint(x: minX, y: minY))
        }
        context.closePath()
    }

    private func roundedRectCornerSet(_ corners: String?) -> Set<Character> {
        guard let corners, corners.isEmpty == false else {
            return Set("1234")
        }
        return Set(corners.filter { "1234".contains($0) })
    }
}
#endif
