import Foundation
import Testing

@testable import SwiftTerm

final class VTGGraphicsSceneSpriteTests {
    @Test func vectorSpriteUploadSharesSpritePlacementAndTransforms() {
        let scene = VTGGraphicsScene()

        scene.apply(command(
            "vectorSpriteUpload",
            ["id": "ship", "width": "40", "height": "30", "stroke": "#5eead4", "fill": "#07111d", "lineWidth": "2"],
            payload: "M 20 0 L 40 30 L 20 22 L 0 30 Z"
        ))
        scene.apply(command("sprite", ["id": "ship1", "image": "ship", "x": "10", "y": "20", "rotation": "5", "scale": "1.5", "anchorX": "0.25", "anchorY": "0.75"]))
        scene.apply(command("spriteTransform", ["id": "ship1", "x": "30", "y": "40", "rotation": "15", "scale": "2"]))
        scene.apply(command("spriteAnchor", ["id": "ship1", "anchorX": "2", "anchorY": "-1"]))

        #expect(scene.vectorSpriteAsset(id: "ship")?.width == 40)
        #expect(scene.primitives.count == 1)
        guard case .sprite(_, let assetID, let x, let y, let rotation, let scale, let anchorX, let anchorY) = scene.primitives[0] else {
            Issue.record("Expected retained vector sprite instance")
            return
        }
        #expect(assetID == "ship")
        #expect(x == 30)
        #expect(y == 40)
        #expect(rotation == 15)
        #expect(scale == 2)
        #expect(anchorX == 1)
        #expect(anchorY == 0)
    }

    @Test func spriteUploadsRejectInvalidIDsAndRespectAssetLimit() {
        let scene = VTGGraphicsScene()
        let payload = Data([1]).base64EncodedString()

        scene.apply(command("spriteUpload", ["id": "bad-id", "format": "png", "width": "1", "height": "1"], payload: payload))
        scene.apply(command("spriteUpload", ["id": "bad id", "format": "png", "width": "1", "height": "1"], payload: payload))
        scene.apply(command("spriteUpload", ["id": String(repeating: "a", count: 65), "format": "png", "width": "1", "height": "1"], payload: payload))
        #expect(scene.spriteAssets.isEmpty)

        for index in 0..<256 {
            scene.apply(command("spriteUpload", ["id": "s\(index)", "format": "png", "width": "1", "height": "1"], payload: payload))
        }
        #expect(scene.spriteAssets.count == 256)

        scene.apply(command("spriteUpload", ["id": "s256", "format": "png", "width": "1", "height": "1"], payload: payload))
        #expect(scene.spriteAsset(id: "s256") == nil)
    }

    @Test func duplicateSpriteUploadReplacesAssetAcrossBitmapAndVectorStores() {
        let scene = VTGGraphicsScene()
        let bitmapPayload = Data([1]).base64EncodedString()
        let replacementPayload = Data([2]).base64EncodedString()

        scene.apply(command("spriteUpload", ["id": "ship", "format": "png", "width": "10", "height": "20"], payload: bitmapPayload))
        #expect(scene.spriteAsset(id: "ship")?.width == 10)
        #expect(scene.spriteAsset(id: "ship")?.base64 == bitmapPayload)

        scene.apply(command("spriteUpload", ["id": "ship", "format": "jpeg", "width": "30", "height": "40"], payload: replacementPayload))
        #expect(scene.spriteAssets.count == 1)
        #expect(scene.spriteAsset(id: "ship")?.format == "jpeg")
        #expect(scene.spriteAsset(id: "ship")?.width == 30)
        #expect(scene.spriteAsset(id: "ship")?.base64 == replacementPayload)

        scene.apply(command(
            "vectorSpriteUpload",
            ["id": "ship", "width": "50", "height": "60", "stroke": "#5eead4"],
            payload: "M 0 0 L 50 30 L 0 60 Z"
        ))
        #expect(scene.spriteAsset(id: "ship") == nil)
        #expect(scene.vectorSpriteAsset(id: "ship")?.width == 50)

        scene.apply(command("spriteUpload", ["id": "ship", "format": "png", "width": "70", "height": "80"], payload: bitmapPayload))
        #expect(scene.vectorSpriteAsset(id: "ship") == nil)
        #expect(scene.spriteAsset(id: "ship")?.width == 70)
    }

    @Test func spriteRemoveAndClearRemoveAssetsAndDependentInstancesOnly() {
        let scene = VTGGraphicsScene()
        let payload = Data([1]).base64EncodedString()

        scene.apply(command("rect", ["id": "background", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("spriteUpload", ["id": "enemy", "format": "png", "width": "8", "height": "8"], payload: payload))
        scene.apply(command("spriteUpload", ["id": "player", "format": "png", "width": "8", "height": "8"], payload: payload))
        scene.apply(command("sprite", ["id": "enemy1", "image": "enemy", "x": "10", "y": "10", "layer": "2"]))
        scene.apply(command("sprite", ["id": "enemy2", "image": "enemy", "x": "20", "y": "10", "layer": "2"]))
        scene.apply(command("sprite", ["id": "player1", "image": "player", "x": "30", "y": "10", "layer": "3"]))

        scene.apply(command("spriteRemove", ["id": "enemy"]))

        #expect(scene.spriteAsset(id: "enemy") == nil)
        #expect(scene.spriteAsset(id: "player") != nil)
        #expect(scene.primitives.map(\.id).sorted() == ["background", "player1"])
        #expect(scene.layersByID["enemy1"] == nil)
        #expect(scene.layersByID["enemy2"] == nil)
        #expect(scene.layersByID["player1"] == 3)

        scene.apply(command("spriteClear"))

        #expect(scene.spriteAssets.isEmpty)
        #expect(scene.vectorSpriteAssets.isEmpty)
        #expect(scene.primitives.map(\.id) == ["background"])
        #expect(scene.layersByID["player1"] == nil)
    }

    private func command(
        _ name: String,
        _ parameters: [String: String] = [:],
        payload: String? = nil
    ) -> VectorTerminalGraphicsCommand {
        VectorTerminalGraphicsCommand(
            name: name,
            parameters: parameters,
            payload: payload
        )
    }
}
