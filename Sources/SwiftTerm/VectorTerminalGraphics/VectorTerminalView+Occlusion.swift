#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Text occlusion and raster text for the terminal view (WINDOW_PLAN.md
/// Phases 1 and 5): the per-frame work that keeps the overlay's text mask and
/// raster framebuffer in step with the text on screen.
extension VectorTerminalView {
    /// The text mask for `scene`, or nil when no layer asked for one.
    ///
    /// - Parameter inLockedCanvas: Express the mask in a locked screen's
    ///   pixels, as the CoreGraphics overlay draws; otherwise in view points,
    ///   as the Metal planes draw.
    func currentVTGTextMask(for scene: VTGGraphicsScene, inLockedCanvas: Bool) -> VTGOcclusionMask? {
        guard scene.usesTextOcclusion, let cell = currentVTGCellSize() else {
            return nil
        }
        var cellWidth = cell.width
        var cellHeight = cell.height
        if inLockedCanvas, let locked = vtgOverlayView.lockedCanvas, bounds.width > 0, bounds.height > 0 {
            cellWidth *= Double(locked.width) / Double(bounds.width)
            cellHeight *= Double(locked.height) / Double(bounds.height)
        }
        return vtgTextMaskBuilder.mask(for: getTerminal(), cellWidth: cellWidth, cellHeight: cellHeight)
    }

    /// Give the overlay the mask for the text on screen now. Called from the
    /// terminal's own draw passes, so a window drawn in plain text re-masks
    /// the overlay without any VTG command.
    func refreshVTGOverlayTextMask() {
        let mask = vtgOverlayView.scene.flatMap { currentVTGTextMask(for: $0, inLockedCanvas: true) }
        if vtgOverlayView.textMask != mask {
            vtgOverlayView.textMask = mask
        }
    }

    /// Apply what changed in the raster framebuffer since the overlay last drew.
    func applyVTGRaster() {
        let controller = vtgSession.controller
        guard controller.isRasterTextErasing, let cell = currentVTGCellSize(),
              bounds.width > 0, bounds.height > 0 else {
            return
        }
        let locked = vtgOverlayView.lockedCanvas
        let canvasSize = locked.map { CGSize(width: $0.width, height: $0.height) } ?? bounds.size
        let lockScale = bounds.width / max(1, canvasSize.width)
        vtgRasterBitmap.apply(controller.rasterCanvas.takeOperations(), overlay: vtgOverlayView,
                              scene: controller.scene, canvasSize: canvasSize,
                              cellSize: (cell.width / Double(lockScale), cell.height / Double(lockScale)),
                              scale: backingScaleFactor() * lockScale)
        let buffer = getTerminal().buffer
        vtgOverlayView.rasterVisible = buffer.yDisp == buffer.yBase
    }

    /// Raster mode with `text=erases`: the terminal reports writes to the
    /// canvas only while a program has that mode on.
    func setupVTGRasterText() {
        vtgSession.controller.advertisesRasterText = true
        vtgSession.rasterCanvasDidChange = { [weak self] canvas in
            guard let self else { return }
            self.getTerminal().cellWriteObserver = canvas
            canvas?.didChange = { [weak self] in self?.vtgOverlayView.vtgSetNeedsDisplay() }
            self.vtgOverlayView.rasterBitmap = canvas == nil ? nil : self.vtgRasterBitmap
            if canvas == nil {
                self.vtgRasterBitmap.release()
            }
        }
        vtgOverlayView.rasterUpdate = { [weak self] in self?.applyVTGRaster() }
    }
}
#endif
