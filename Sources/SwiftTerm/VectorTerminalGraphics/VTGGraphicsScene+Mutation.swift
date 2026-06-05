import Foundation

/// Retained primitive and scene-wide state mutation helpers for ``VTGGraphicsScene``.
extension VTGGraphicsScene {
    func clear() {
        primitives.removeAll()
        spriteAssets.removeAll()
        vectorSpriteAssets.removeAll()
        indexesByID.removeAll()
        layersByID.removeAll()
        layerOffsets.removeAll()
        layerClips.removeAll()
        layerAlphas.removeAll()
        viewportModes.removeAll()
        viewportScales.removeAll()
        hitRegions.removeAll()
        defaultLayer = VTGLayerModel.defaultDrawingLayer
    }

    func upsert(_ primitive: VTGPrimitive?, command: VectorTerminalGraphicsCommand) {
        guard let primitive else {
            return
        }
        layersByID[primitive.id] = command.layerValue(default: layersByID[primitive.id] ?? defaultLayer)
        if let index = indexesByID[primitive.id] {
            primitives[index] = primitive
        } else {
            indexesByID[primitive.id] = primitives.count
            primitives.append(primitive)
        }
    }

    func remove(id: String) {
        guard let index = indexesByID[id] else {
            return
        }
        primitives.remove(at: index)
        layersByID.removeValue(forKey: id)
        // Removing from an array shifts later indexes, so rebuild the small
        // lookup table rather than trying to patch every affected index.
        indexesByID = Dictionary(uniqueKeysWithValues: primitives.enumerated().map { ($0.element.id, $0.offset) })
    }

    func setPrimitiveLayer(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              indexesByID[id] != nil else {
            return
        }
        layersByID[id] = command.layerValue(default: layersByID[id] ?? defaultLayer)
    }
}
