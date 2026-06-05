import Foundation

/// Retained sprite instance helpers for the VTG scene.
extension VTGGraphicsScene {
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
}
