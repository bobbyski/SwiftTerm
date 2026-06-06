import Foundation

/// Sprite asset removal helpers for the VTG scene.
extension VTGGraphicsScene {
    func removeSpriteAsset(id: String) {
        spriteAssets.removeValue(forKey: id)
        vectorSpriteAssets.removeValue(forKey: id)
        indexedSpriteAssets.removeValue(forKey: id)
        var removedPrimitiveIDs: [String] = []
        primitives.removeAll { primitive in
            if case .sprite(_, let assetID, _, _, _, _, _, _) = primitive {
                let shouldRemove = assetID == id
                if shouldRemove {
                    removedPrimitiveIDs.append(primitive.id)
                }
                return shouldRemove
            }
            return false
        }
        for primitiveID in removedPrimitiveIDs {
            layersByID.removeValue(forKey: primitiveID)
        }
        rebuildIndexes()
    }

    func removeAllSpriteAssets() {
        spriteAssets.removeAll()
        vectorSpriteAssets.removeAll()
        indexedSpriteAssets.removeAll()
        var removedPrimitiveIDs: [String] = []
        primitives.removeAll { primitive in
            if case .sprite = primitive {
                removedPrimitiveIDs.append(primitive.id)
                return true
            }
            return false
        }
        for primitiveID in removedPrimitiveIDs {
            layersByID.removeValue(forKey: primitiveID)
        }
        rebuildIndexes()
    }
}
