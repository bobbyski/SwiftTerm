import Foundation

/// Sprite asset upload and removal helpers for the VTG scene.
extension VTGGraphicsScene {
    var uploadedSpriteAssetCount: Int {
        spriteAssets.count + vectorSpriteAssets.count + indexedSpriteAssets.count
    }

    func hasUploadedSpriteAsset(id: String) -> Bool {
        spriteAssets[id] != nil || vectorSpriteAssets[id] != nil || indexedSpriteAssets[id] != nil
    }

    func uploadSprite(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              Self.isValidIdentifier(id),
              hasUploadedSpriteAsset(id: id) || uploadedSpriteAssetCount < spriteAssetLimit,
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
        indexedSpriteAssets.removeValue(forKey: id)
        spriteAssets[id] = VTGSpriteAsset(
            id: id,
            format: format == "jpg" ? "jpeg" : format,
            width: width,
            height: height,
            data: data,
            base64: payload,
            filter: command.spriteFilter()
        )
    }

    func uploadVectorSprite(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              Self.isValidIdentifier(id),
              hasUploadedSpriteAsset(id: id) || uploadedSpriteAssetCount < spriteAssetLimit,
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
        indexedSpriteAssets.removeValue(forKey: id)
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

    func uploadIndexedSprite(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              Self.isValidIdentifier(id),
              hasUploadedSpriteAsset(id: id) || uploadedSpriteAssetCount < spriteAssetLimit,
              let payload = command.payload else {
            return
        }
        let rawWidth = command.double("width", default: command.double("w"))
        let rawHeight = command.double("height", default: command.double("h"))
        guard rawWidth.isFinite, rawHeight.isFinite else {
            return
        }
        let width = Int(rawWidth)
        let height = Int(rawHeight)
        guard width > 0, height > 0 else {
            return
        }
        let palette = parseIndexedSpritePalette(command.parameters["palette"])
        guard palette.isEmpty == false else {
            return
        }
        let pixels = parseIndexedSpritePixels(payload)
        guard pixels.count == width * height else {
            return
        }
        let transparentIndex = command.parameters["transparent"].flatMap(Int.init)
        let validPixels = pixels.allSatisfy { pixel in
            if let transparentIndex, pixel == transparentIndex {
                return true
            }
            return pixel >= 0 && pixel < palette.count
        }
        guard validPixels else {
            return
        }
        spriteAssets.removeValue(forKey: id)
        vectorSpriteAssets.removeValue(forKey: id)
        indexedSpriteAssets[id] = VTGIndexedSpriteAsset(
            id: id,
            width: width,
            height: height,
            palette: palette,
            pixels: pixels,
            transparentIndex: transparentIndex,
            payload: payload,
            filter: command.spriteFilter(default: .nearest)
        )
    }

    private func parseIndexedSpritePalette(_ rawPalette: String?) -> [VTGColor] {
        guard let rawPalette else {
            return []
        }
        return rawPalette
            .split(separator: "|")
            .compactMap { VTGColor(hex: String($0)) }
    }

    private func parseIndexedSpritePixels(_ payload: String) -> [Int] {
        payload
            .split { character in
                character == "," || character == " " || character == "\n" || character == "\r" || character == "\t"
            }
            .compactMap { Int($0) }
    }
}
