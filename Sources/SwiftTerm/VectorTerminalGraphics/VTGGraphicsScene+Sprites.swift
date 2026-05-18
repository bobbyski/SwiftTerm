import Foundation

/// Sprite asset and retained sprite instance helpers for the VTG scene.
extension VTGGraphicsScene {
    func uploadSprite(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              Self.isValidIdentifier(id),
              spriteAssets[id] != nil || vectorSpriteAssets[id] != nil || (spriteAssets.count + vectorSpriteAssets.count) < spriteAssetLimit,
              let payload = command.payload,
              let data = Data(base64Encoded: payload) else {
            return
        }
        let format = (command.parameters["format"] ?? "png").lowercased()
        guard format == "png" || format == "jpeg" || format == "jpg" else {
            return
        }
        let width = command.double("width", default: command.double("w"))
        let height = command.double("height", default: command.double("h"))
        guard width > 0, height > 0 else {
            return
        }
        vectorSpriteAssets.removeValue(forKey: id)
        spriteAssets[id] = VTGSpriteAsset(
            id: id,
            format: format == "jpg" ? "jpeg" : format,
            width: width,
            height: height,
            data: data,
            base64: payload
        )
    }

    func uploadVectorSprite(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              Self.isValidIdentifier(id),
              vectorSpriteAssets[id] != nil || spriteAssets[id] != nil || (spriteAssets.count + vectorSpriteAssets.count) < spriteAssetLimit,
              let payload = command.payload,
              let commands = VTGPathParser.parse(payload),
              commands.isEmpty == false else {
            return
        }
        let width = command.double("width", default: command.double("w"))
        let height = command.double("height", default: command.double("h"))
        guard width > 0, height > 0 else {
            return
        }
        spriteAssets.removeValue(forKey: id)
        vectorSpriteAssets[id] = VTGVectorSpriteAsset(
            id: id,
            width: width,
            height: height,
            commands: commands,
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("lineWidth", default: command.double("width", default: 1))),
            payload: payload
        )
    }

    func parseSprite(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"],
              Self.isValidIdentifier(id),
              let assetID = command.parameters["image"] ?? command.parameters["asset"],
              spriteAssets[assetID] != nil || vectorSpriteAssets[assetID] != nil else {
            return nil
        }
        return .sprite(
            id: id,
            assetID: assetID,
            x: command.double("x"),
            y: command.double("y"),
            rotation: command.double("rotation"),
            scale: max(0.01, command.double("scale", default: 1)),
            anchorX: command.normalizedDouble("anchorX", default: 0.5),
            anchorY: command.normalizedDouble("anchorY", default: 0.5)
        )
    }

    struct SpriteUpdateOptions: OptionSet {
        let rawValue: Int

        static let position = SpriteUpdateOptions(rawValue: 1 << 0)
        static let rotation = SpriteUpdateOptions(rawValue: 1 << 1)
        static let scale = SpriteUpdateOptions(rawValue: 1 << 2)
        static let anchor = SpriteUpdateOptions(rawValue: 1 << 3)
    }

    func transformSprite(_ command: VectorTerminalGraphicsCommand, updates: SpriteUpdateOptions) {
        guard let id = command.parameters["id"],
              let index = indexesByID[id],
              case .sprite(let spriteID, let assetID, let currentX, let currentY, let currentRotation, let currentScale, let currentAnchorX, let currentAnchorY) = primitives[index] else {
            return
        }
        let x = updates.contains(.position) ? command.double("x", default: currentX) : currentX
        let y = updates.contains(.position) ? command.double("y", default: currentY) : currentY
        let rotation = updates.contains(.rotation) ? command.double("rotation", default: currentRotation) : currentRotation
        let scale = updates.contains(.scale) ? max(0.01, command.double("scale", default: currentScale)) : currentScale
        let anchorX = updates.contains(.anchor) ? command.normalizedDouble("anchorX", default: currentAnchorX) : currentAnchorX
        let anchorY = updates.contains(.anchor) ? command.normalizedDouble("anchorY", default: currentAnchorY) : currentAnchorY
        primitives[index] = .sprite(id: spriteID, assetID: assetID, x: x, y: y, rotation: rotation, scale: scale, anchorX: anchorX, anchorY: anchorY)
    }

    func removeSpriteAsset(id: String) {
        spriteAssets.removeValue(forKey: id)
        vectorSpriteAssets.removeValue(forKey: id)
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
