import Foundation

/// Raster mode — drawing painted into the text plane and not retained.
///
/// ```text
///   retained (default)           raster mode
///   ──────────────────           ─────────────────────────────
///   layers 1…4, above text       layer 0, the text's own plane
///   one object per id            one object per command
///   delete(id:) removes it       nothing to remove
/// ```
///
/// **For simulators of machines with a single framebuffer.** On those, a
/// plotted point is not an object: it is a lit pixel the text can overwrite,
/// and it scrolls away with the line it sits on. A retained scene cannot say
/// that — its circle survives the scroll and waits to be deleted by id — so a
/// simulator drawing into the retained scene produces graphics that float above
/// the text they belong to.
///
/// **Nothing else about the protocol changes.** The guest keeps sending the
/// same commands with the same parameters, ids included. The host rewrites each
/// drawing command as it passes: onto the text plane, under an id of the host's
/// own that nothing will ever reuse. So the same program runs either way, and
/// `rasterMode` is the only thing it has to learn.
extension VTGHostController {
    /// The drawing verbs that create a retained primitive, and so need
    /// rewriting. Everything else — `clear`, `defaultLayer`, sprite uploads,
    /// queries — passes through untouched.
    static let rasterDrawingCommands: Set<String> = [
        "pixel", "line", "draw", "curve", "triangle", "path", "rect", "circle",
        "ellipse", "text", "image", "sprite", "styledText", "attrText", "textBox",
    ]

    /// Turn raster mode on or off, clearing the scene either way.
    ///
    /// Cleared because the two models cannot both be addressed: objects drawn
    /// before the switch would stay on screen under ids the guest can no longer
    /// use, and raster pixels would outlive the mode that explains them.
    ///
    /// - Parameter textErases: `rasterMode,enabled=1,text=erases`: draw into
    ///   `rasterCanvas`, a framebuffer the text overwrites, instead of onto
    ///   layer 0. Plain raster mode is unchanged (WINDOW_PLAN.md rule 3).
    func setRasterMode(_ enabled: Bool, textErases: Bool = false) {
        let erasing = enabled && textErases
        guard enabled != isRasterMode || erasing != isRasterTextErasing else {
            return
        }
        isRasterMode = enabled
        let wasErasing = isRasterTextErasing
        isRasterTextErasing = erasing
        rasterObjectCount = 0
        // Uploaded sprite assets stay: raster mode draws sprites too, and it
        // is the drawing's ids, not the pictures, that cannot carry across.
        scene.clearDrawing()
        pendingFrame = nil
        if erasing || wasErasing {
            rasterCanvas.clear()
            rasterTextModeDidChange?(erasing ? rasterCanvas : nil)
        }
    }

    /// With `text=erases`, send a drawing command to the raster canvas instead
    /// of the scene. Returns whether the command was taken.
    ///
    /// The command is parsed by the scene that would have kept it — so sprite
    /// assets, text styles and refusals work exactly as before — and the
    /// primitive is then taken back out, so nothing is retained.
    func drawIntoRasterCanvas(_ command: VectorTerminalGraphicsCommand) -> Bool {
        if command.name == "clear" {
            // A screen clear erases the framebuffer too; the scene still
            // handles the rest of `clear`.
            rasterCanvas.clear()
            return false
        }
        guard Self.rasterDrawingCommands.contains(command.name) else {
            return false
        }
        let rewritten = rasterized(command)
        let scene = activeScene
        scene.apply(rewritten)
        if let id = rewritten.parameters["id"], let index = scene.indexesByID[id] {
            let primitive = scene.primitives[index]
            scene.remove(id: id)
            rasterCanvas.draw(primitive)
        }
        return true
    }

    /// The command as the scene should see it while raster mode is on.
    ///
    /// The id is the host's own counter rather than the guest's, so drawing the
    /// same id twice paints twice instead of replacing — which is what a
    /// framebuffer does — and `delete` from the guest finds nothing.
    func rasterized(_ command: VectorTerminalGraphicsCommand) -> VectorTerminalGraphicsCommand {
        guard Self.rasterDrawingCommands.contains(command.name) else {
            return command
        }
        rasterObjectCount += 1
        var parameters = command.parameters
        parameters["id"] = "vtg-raster-\(rasterObjectCount)"
        parameters["layer"] = String(VTGLayerModel.textPlaneLayer)
        return VectorTerminalGraphicsCommand(
            name: command.name,
            parameters: parameters,
            payload: command.payload
        )
    }
}
