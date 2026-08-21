import Foundation

/// Layer, clipping, alpha, and hit-region mutation helpers for the VTG scene.
extension VTGGraphicsScene {
    func setLayerScroll(_ command: VectorTerminalGraphicsCommand) {
        let layer = command.layerValue(default: defaultLayer)
        guard VTGLayerModel.isScrollable(layer) else {
            return
        }
        layerOffsets[layer] = VTGLayerOffset(
            x: command.double("x", default: offset(for: layer).x),
            y: command.double("y", default: offset(for: layer).y)
        )
    }

    /// `layerAnchor,layer=N,mode=text|screen[,line=<absolute buffer line>]`
    ///
    /// Applies to **every** layer including -1. `layerScroll` deliberately
    /// refuses the under-text plane, but anchoring is not scrolling: it is a
    /// statement about where the layer belongs in the document, and inline
    /// chrome drawn beneath its own text is exactly the case that needs it.
    func setLayerTextAnchor(_ command: VectorTerminalGraphicsCommand) {
        let layer = command.layerValue(default: defaultLayer)
        guard VTGLayerModel.supportedRange.contains(layer) else {
            return
        }
        let mode = command.parameters["mode"] ?? "text"
        guard mode == "text" else {
            // Back to viewport-fixed, and the offset the anchor was driving
            // goes with it — leaving it behind would strand the layer wherever
            // the last scroll happened to put it.
            layerTextAnchors.removeValue(forKey: layer)
            layerOffsets.removeValue(forKey: layer)
            return
        }
        // A missing line means "here": the host substitutes the current line
        // before the command reaches the scene, since only it knows the buffer.
        layerTextAnchors[layer] = VTGTextAnchor(line: Int(command.double("line", default: 0)))
    }

    /// Recomputes anchored layers' offsets for the current scroll position.
    ///
    /// Driven by the terminal on every scroll and before each frame, not by the
    /// client: the client names a line, and where that line sits on screen is
    /// the terminal's business.
    ///
    /// - Parameters:
    ///   - topLine: The absolute buffer line at the top of the view (`yDisp`).
    ///   - cellHeight: Height of one text row, in the same pixels VTG draws in.
    public func updateTextAnchoredLayers(topLine: Int, cellHeight: Double) {
        guard !layerTextAnchors.isEmpty, cellHeight > 0 else {
            return
        }
        for (layer, anchor) in layerTextAnchors {
            // Positive as the line sits below the top of the view, negative once
            // it has scrolled above it — the layer keeps drawing, off-screen,
            // rather than being deleted, so scrolling back brings it right back.
            let y = Double(anchor.line - topLine) * cellHeight
            layerOffsets[layer] = VTGLayerOffset(x: offset(for: layer).x, y: y)
        }
    }

    func setLayerAlpha(_ command: VectorTerminalGraphicsCommand) {
        let layer = command.layerValue(default: defaultLayer)
        guard VTGLayerModel.isScrollable(layer) else {
            return
        }
        let alpha = min(1, max(0, command.double("alpha", default: 1)))
        if alpha >= 0.999 {
            layerAlphas.removeValue(forKey: layer)
        } else {
            layerAlphas[layer] = alpha
        }
    }

    func setLayerClip(_ command: VectorTerminalGraphicsCommand) {
        let layer = command.layerValue(default: defaultLayer)
        guard VTGLayerModel.supportedRange.contains(layer) else {
            return
        }
        let width = command.double("w", default: command.double("width"))
        let height = command.double("h", default: command.double("height"))
        guard width > 0, height > 0 else {
            return
        }
        layerClips[layer] = VTGLayerClip(
            x: command.double("x"),
            y: command.double("y"),
            width: width,
            height: height
        )
    }

    func clearLayerClip(_ command: VectorTerminalGraphicsCommand) {
        let layer = command.layerValue(default: defaultLayer)
        layerClips.removeValue(forKey: layer)
    }

    func upsertHitRegion(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              Self.isValidIdentifier(id) else {
            return
        }
        let width = command.double("w", default: command.double("width"))
        let height = command.double("h", default: command.double("height"))
        guard width > 0, height > 0 else {
            return
        }
        let order = hitRegions[id]?.order ?? nextHitOrder
        if hitRegions[id] == nil {
            nextHitOrder += 1
        }
        let rawTarget = command.parameters["target"]
        let target = rawTarget.flatMap { Self.isValidIdentifier($0) ? $0 : nil }
        hitRegions[id] = VTGHitRegion(
            id: id,
            target: target,
            layer: command.layerValue(default: defaultLayer),
            x: command.double("x"),
            y: command.double("y"),
            width: width,
            height: height,
            order: order
        )
    }

    func clearHitRegion(_ command: VectorTerminalGraphicsCommand) {
        if let id = command.parameters["id"] {
            hitRegions.removeValue(forKey: id)
        } else if let layerValue = command.parameters["layer"].flatMap(Int.init).map(VTGLayerModel.clamped) {
            hitRegions = hitRegions.filter { $0.value.layer != layerValue }
        } else {
            hitRegions.removeAll()
        }
    }
}
