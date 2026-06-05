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
        guard layer >= 0 else {
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
