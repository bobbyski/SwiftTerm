#if os(macOS) || os(iOS)
import CoreGraphics
import Foundation

/// The pixels of a VTG raster framebuffer on Apple platforms (WINDOW_PLAN.md
/// Phase 5): a bitmap the overlay view draws first, under layers 1…4.
///
/// ```text
///   .draw        → draw the primitive into the bitmap, as the overlay would
///   .eraseCells  → clear those cells (text was written there)
///   .scroll      → move the region's pixel rows, and blank the rows uncovered
///   .clear       → clear everything
/// ```
///
/// The overlay sits above the terminal text in both Mac renderers, so one
/// bitmap serves CoreGraphics and Metal alike: drawing covers text written
/// before it, and text written after it erases it.
public final class VTGRasterBitmap {
    private var context: CGContext?
    private var pixelWidth = 0
    private var pixelHeight = 0
    /// Canvas points to bitmap pixels.
    private var scale: CGFloat = 1

    public init() {}

    /// Apply queued operations.
    ///
    /// - Parameters:
    ///   - operations: From `VTGRasterCanvas.takeOperations()`, oldest first.
    ///   - overlay: Draws primitives the way the overlay layers are drawn.
    ///   - scene: Sprite assets and text styles for the primitives.
    ///   - canvasSize: The canvas, in points (the locked screen, when locked).
    ///   - cellSize: One text cell, in canvas points.
    ///   - scale: Canvas points to pixels: backing scale, times any lock scale.
    func apply(_ operations: [VTGRasterOperation], overlay: VTGOverlayView, scene: VTGGraphicsScene,
               canvasSize: CGSize, cellSize: (width: Double, height: Double), scale: CGFloat) {
        guard let context = bitmap(canvasSize: canvasSize, scale: scale) else {
            return
        }
        for operation in operations {
            switch operation {
            case .draw(let primitive):
                vtgPushDrawingContext(context)
                overlay.drawPrimitive(primitive, in: context, scene: scene)
                vtgPopDrawingContext()
            case .clear:
                context.clear(CGRect(origin: .zero, size: canvasSize))
            case .eraseCells(let row, let columns):
                context.clear(CGRect(x: Double(columns.lowerBound) * cellSize.width,
                                     y: Double(row) * cellSize.height,
                                     width: Double(columns.count) * cellSize.width,
                                     height: cellSize.height))
            case .scroll(let top, let bottom, let count):
                scrollRows(top: top, bottom: bottom, count: count, cellHeight: cellSize.height)
            }
        }
    }

    /// Draw the framebuffer into a top-left-origin context covering `bounds`.
    func draw(in target: CGContext, bounds: CGRect) {
        guard let image = context?.makeImage() else { return }
        target.saveGState()
        // A bitmap image draws bottom-up; the overlay's context is flipped.
        target.translateBy(x: bounds.minX, y: bounds.maxY)
        target.scaleBy(x: 1, y: -1)
        target.interpolationQuality = .none
        target.draw(image, in: CGRect(origin: .zero, size: bounds.size))
        target.restoreGState()
    }

    /// Let go of the pixels, for when raster text mode ends.
    public func release() {
        context = nil
        pixelWidth = 0
        pixelHeight = 0
    }

    /// The bitmap, made or remade for this size. A new size is a new,
    /// empty framebuffer, as on the machine raster mode imitates.
    private func bitmap(canvasSize: CGSize, scale: CGFloat) -> CGContext? {
        let width = max(1, Int((canvasSize.width * scale).rounded()))
        let height = max(1, Int((canvasSize.height * scale).rounded()))
        if let context, width == pixelWidth, height == pixelHeight, scale == self.scale {
            return context
        }
        guard let made = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            print("VTGRasterBitmap: could not make a \(width)x\(height) bitmap; raster drawing skipped")
            return nil
        }
        // Draw in canvas points with the origin at the top left.
        made.translateBy(x: 0, y: CGFloat(height))
        made.scaleBy(x: scale, y: -scale)
        context = made
        pixelWidth = width
        pixelHeight = height
        self.scale = scale
        return made
    }

    /// Move rows `top...bottom` up by `count` rows (down when negative) in
    /// the pixel memory, which is stored top row first, and blank what is
    /// uncovered.
    private func scrollRows(top: Int, bottom: Int, count: Int, cellHeight: Double) {
        guard let context, let data = context.data, count != 0 else { return }
        let bytesPerRow = context.bytesPerRow
        let rowPixels = Double(cellHeight) * Double(scale)
        let regionTop = max(0, min(pixelHeight, Int((Double(top) * rowPixels).rounded())))
        let regionBottom = max(0, min(pixelHeight, Int((Double(bottom + 1) * rowPixels).rounded())))
        let shift = Int((Double(abs(count)) * rowPixels).rounded())
        let height = regionBottom - regionTop
        guard height > 0 else { return }
        let base = data.assumingMemoryBound(to: UInt8.self)
        if shift >= height {
            memset(base + regionTop * bytesPerRow, 0, height * bytesPerRow)
            return
        }
        let kept = height - shift
        if count > 0 {
            memmove(base + regionTop * bytesPerRow, base + (regionTop + shift) * bytesPerRow, kept * bytesPerRow)
            memset(base + (regionTop + kept) * bytesPerRow, 0, shift * bytesPerRow)
        } else {
            memmove(base + (regionTop + shift) * bytesPerRow, base + regionTop * bytesPerRow, kept * bytesPerRow)
            memset(base + regionTop * bytesPerRow, 0, shift * bytesPerRow)
        }
    }
}
#endif
