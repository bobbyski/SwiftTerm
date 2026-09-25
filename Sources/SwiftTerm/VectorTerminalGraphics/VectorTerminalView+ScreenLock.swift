#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A locked screen in the view: an exact resolution and text grid, drawn at a
/// whole-number multiple and centred (VTG `screenLock`).
///
/// **The terminal view is the screen.** Locking does not move the view — a host
/// owns that — it makes the view's contents the locked screen: the text grid
/// becomes the locked columns and rows with the cell the screen implies, and
/// graphics draw in locked pixels, scaled up to the view.
///
/// So a host that wants the clean reproduction the lock is for gives the view
/// the rectangle ``VectorTerminalView/vtgScreenRect(fitting:)`` returns —
/// a whole multiple of the screen, centred, the rest left as border.
/// ``VTGTerminalOverlayContainerView`` does this for its terminal, and an
/// embedder with its own layout does it in `onScreenLockChange`. A host that
/// ignores it still gets a working terminal of the right grid; what it loses is
/// the square pixels, because its view is not a multiple of the screen.
extension VectorTerminalView {
    /// The screen a program locked, or nil for a normal terminal.
    public var vtgScreenLock: VTGScreenLock? {
        vtgSession.screenLock
    }

    /// Where the locked screen should sit in a frame this size: the largest
    /// whole multiple that fits, centred. Nil when nothing is locked.
    public func vtgScreenRect(fitting frame: CGSize) -> CGRect? {
        guard let lock = vtgScreenLock,
              let layout = lock.layout(inWidth: Double(frame.width), frameHeight: Double(frame.height))
        else {
            return nil
        }
        return CGRect(x: layout.x, y: layout.y, width: layout.width, height: layout.height)
    }

    /// Apply the current lock to this view: the grid, the cell, the font, and
    /// the canvas graphics draw in. Called when a program locks or unlocks,
    /// and whenever the view's size changes under a lock.
    func applyVTGScreenLock() {
        let lock = vtgScreenLock
        vtgOverlayView.lockedCanvas = lock?.canvas
        vtgPageView.lockedCanvas = lock?.canvas

        guard let lock else {
            guard vtgLockedCellDimension != nil else {
                return
            }
            // Back to a terminal: the font decides the cell again, and the grid
            // is whatever now fits.
            vtgLockedCellDimension = nil
            font = vtgFontBeforeScreenLock ?? font
            vtgFontBeforeScreenLock = nil
            return
        }
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        let cell = CGSize(
            width: max(1, bounds.width / CGFloat(lock.columns)),
            height: max(1, bounds.height / CGFloat(lock.rows))
        )
        guard cell != vtgLockedCellDimension else {
            return
        }
        if vtgFontBeforeScreenLock == nil {
            vtgFontBeforeScreenLock = font
        }
        vtgLockedCellDimension = cell
        // Setting the font resets the cell and the grid; the size is the
        // largest whose glyphs fit the locked cell, so the text fills the
        // screen as the machine's own font would.
        font = VectorTerminalView.vtgFont(vtgFontBeforeScreenLock ?? font, fitting: cell)
        resize(cols: lock.columns, rows: lock.rows)
        vtgSetNeedsDisplay()
    }

    /// The largest size of `font` whose cell fits inside `cell`.
    ///
    /// Measured the way ``computeFontDimensions()`` measures — ascent, descent
    /// and leading for the height, a `W` for the width — so what is chosen here
    /// is what the renderer will find.
    static func vtgFont(_ font: VTGPlatformFont, fitting cell: CGSize) -> VTGPlatformFont {
        var best = font.withVTGSize(1)
        var low = 1.0
        var high = max(2.0, Double(cell.height) * 2)
        // Twelve halvings settle a point size to well under a tenth of a point.
        for _ in 0..<12 {
            let size = (low + high) / 2
            let candidate = font.withVTGSize(CGFloat(size))
            if candidate.vtgFits(cell) {
                best = candidate
                low = size
            } else {
                high = size
            }
        }
        return best
    }
}

extension VTGPlatformFont {
    func withVTGSize(_ size: CGFloat) -> VTGPlatformFont {
        #if os(macOS)
        return NSFont(descriptor: fontDescriptor, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #else
        return withSize(size)
        #endif
    }

    /// Whether a cell drawn in this font fits inside `cell`.
    func vtgFits(_ cell: CGSize) -> Bool {
        let ctFont = self as CTFont
        let height = ceil(CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont))
        #if os(macOS)
        let width = advancement(forGlyph: glyph(withName: "W")).width
        #else
        let width = ("W" as NSString).size(withAttributes: [.font: self]).width
        #endif
        return ceil(width) <= cell.width && height <= cell.height
    }
}
#endif
