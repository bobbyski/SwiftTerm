import Foundation

/// `screenLock`, `screenUnlock` and `screen?` — a program reproducing a
/// particular machine asks for that machine's screen, and gets it back.
///
/// While a screen is locked the canvas every drawing command addresses is the
/// locked one, whatever the window is doing: `canvas?`, `size?`, `capabilities?`
/// and every `resize` event report it, `glyphSize?` reports the locked cell,
/// and mouse coordinates arrive in it. The window's own size stops being the
/// program's business, which is the point — a 320×200 program should not have
/// to redraw because a person dragged a corner.
extension VTGHostController {
    /// The canvas a program sees: the locked screen, or the real window.
    public func screenCanvas(for canvas: VTGCanvasSize) -> VTGCanvasSize {
        screenLock?.canvas ?? canvas
    }

    /// One character cell as the program sees it: the locked grid's cell, or
    /// whatever the view measured from the font.
    func screenGlyphSize(
        _ glyphSize: (width: Double, height: Double)?
    ) -> (width: Double, height: Double)? {
        guard let lock = screenLock else {
            return glyphSize
        }
        return lock.cellSize
    }

    /// Where the locked screen sits in a frame this size, and at what multiple.
    public func screenLayout(inFrame frame: VTGCanvasSize) -> VTGScreenLock.Layout? {
        screenLock?.layout(inWidth: Double(frame.width), frameHeight: Double(frame.height))
    }

    func screenLockResponses(
        _ command: VectorTerminalGraphicsCommand,
        canvas: VTGCanvasSize
    ) -> [String] {
        let width = Int(command.double("width", default: command.double("w")))
        let height = Int(command.double("height", default: command.double("h")))
        // A program that names a resolution and no grid gets the text grid its
        // cell size implies, rather than a refusal: `cols`/`rows` default to
        // the classic 8×8 character cell.
        let columns = Int(command.double("cols", default: command.double(
            "columns", default: Double(max(1, width / 8)))))
        let rows = Int(command.double("rows", default: Double(max(1, height / 8))))
        guard let lock = VTGScreenLock(width: width, height: height, columns: columns, rows: rows) else {
            return []
        }
        guard lock != screenLock else {
            return [VTGResponseEncoder.screen(fields: lock.responseFields(layout: screenLayout(inFrame: canvas)))]
        }
        screenLock = lock
        screenLockDidChange?(lock)
        return screenChangeResponses(canvas: canvas)
    }

    func screenUnlockResponses(canvas: VTGCanvasSize) -> [String] {
        guard screenLock != nil else {
            return [VTGResponseEncoder.screen(fields: [])]
        }
        screenLock = nil
        screenLockDidChange?(nil)
        return screenChangeResponses(canvas: canvas)
    }

    /// The answer to locking or unlocking: what the screen is now, and — for a
    /// program that subscribed to resizes — the canvas it must now draw for.
    /// The canvas changed even though the window did not.
    private func screenChangeResponses(canvas: VTGCanvasSize) -> [String] {
        var responses = [VTGResponseEncoder.screen(
            fields: screenLock?.responseFields(layout: screenLayout(inFrame: canvas)) ?? []
        )]
        if sendsResizeEvents {
            let reported = reportedCanvas(for: canvas)
            lastReportedCanvas = reported
            responses.append(VTGResponseEncoder.resize(canvas: reported))
        }
        return responses
    }
}
