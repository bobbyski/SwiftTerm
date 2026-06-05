import Foundation

/// Sprite asset upload and removal helpers for the VTG scene.
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
