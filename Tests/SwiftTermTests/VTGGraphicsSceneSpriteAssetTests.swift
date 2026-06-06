import Foundation
import Testing

@testable import SwiftTerm

final class VTGGraphicsSceneSpriteAssetTests {
    @Test func spriteUploadsRejectInvalidIDsAndRespectAssetLimit() {
        let scene = VTGGraphicsScene()
        let payload = Data([1]).base64EncodedString()

        scene.apply(command("spriteUpload", ["id": "bad-id", "format": "png", "width": "1", "height": "1"], payload: payload))
        scene.apply(command("spriteUpload", ["id": "bad id", "format": "png", "width": "1", "height": "1"], payload: payload))
        scene.apply(command("spriteUpload", ["id": String(repeating: "a", count: 65), "format": "png", "width": "1", "height": "1"], payload: payload))
        #expect(scene.spriteAssets.isEmpty)
        #expect(scene.indexedSpriteAssets.isEmpty)

        for index in 0..<256 {
            scene.apply(command("spriteUpload", ["id": "s\(index)", "format": "png", "width": "1", "height": "1"], payload: payload))
        }
        #expect(scene.spriteAssets.count == 256)

        scene.apply(command("spriteUpload", ["id": "s256", "format": "png", "width": "1", "height": "1"], payload: payload))
        #expect(scene.spriteAsset(id: "s256") == nil)
    }

    @Test func indexedSpriteUploadValidatesPayloadAndPalette() {
        let scene = VTGGraphicsScene()

        scene.apply(command("spriteDataUpload", ["id": "bad-id", "width": "2", "height": "2", "palette": "#000000|#5eead4"], payload: "0,1,1,0"))
        scene.apply(command("spriteDataUpload", ["id": "short", "width": "2", "height": "2", "palette": "#000000|#5eead4"], payload: "0,1,1"))
        scene.apply(command("spriteDataUpload", ["id": "palette", "width": "2", "height": "2", "palette": "#nothex"], payload: "0,0,0,0"))
        scene.apply(command("spriteDataUpload", ["id": "range", "width": "2", "height": "2", "palette": "#000000|#5eead4"], payload: "0,1,2,0"))

        #expect(scene.indexedSpriteAssets.isEmpty)

        scene.apply(command("spriteDataUpload", ["id": "basicship", "width": "2", "height": "2", "palette": "#000000|#5eead4", "transparent": "0", "filter": "nearest"], payload: "0,1,1,0"))

        let asset = scene.indexedSpriteAsset(id: "basicship")
        #expect(asset?.width == 2)
        #expect(asset?.height == 2)
        #expect(asset?.pixels == [0, 1, 1, 0])
        #expect(asset?.palette.count == 2)
        #expect(asset?.transparentIndex == 0)
        #expect(asset?.filter == .nearest)
    }

    @Test func bitmapSpriteUploadStoresFilteringHint() {
        let scene = VTGGraphicsScene()
        let payload = Data([1]).base64EncodedString()

        scene.apply(command("spriteUpload", ["id": "smooth", "format": "png", "width": "1", "height": "1"], payload: payload))
        scene.apply(command("spriteUpload", ["id": "sharp", "format": "png", "width": "1", "height": "1", "filter": "nearest"], payload: payload))
        scene.apply(command("spriteUpload", ["id": "unknown", "format": "png", "width": "1", "height": "1", "filter": "crispy"], payload: payload))

        #expect(scene.spriteAsset(id: "smooth")?.filter == .smooth)
        #expect(scene.spriteAsset(id: "sharp")?.filter == .nearest)
        #expect(scene.spriteAsset(id: "unknown")?.filter == .smooth)
    }

    @Test func duplicateSpriteUploadReplacesAssetAcrossBitmapVectorAndIndexedStores() {
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

        scene.apply(command("spriteDataUpload", ["id": "ship", "width": "2", "height": "2", "palette": "#000000|#5eead4", "transparent": "0"], payload: "0,1,1,0"))
        #expect(scene.spriteAsset(id: "ship") == nil)
        #expect(scene.vectorSpriteAsset(id: "ship") == nil)
        #expect(scene.indexedSpriteAsset(id: "ship")?.pixels == [0, 1, 1, 0])

        scene.apply(command("spriteUpload", ["id": "ship", "format": "png", "width": "70", "height": "80"], payload: bitmapPayload))
        #expect(scene.vectorSpriteAsset(id: "ship") == nil)
        #expect(scene.indexedSpriteAsset(id: "ship") == nil)
        #expect(scene.spriteAsset(id: "ship")?.width == 70)
    }

    @Test func spriteRemoveAndClearRemoveAssetsAndDependentInstancesOnly() {
        let scene = VTGGraphicsScene()
        let payload = Data([1]).base64EncodedString()

        scene.apply(command("rect", ["id": "background", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("spriteUpload", ["id": "enemy", "format": "png", "width": "8", "height": "8"], payload: payload))
        scene.apply(command("spriteDataUpload", ["id": "player", "width": "2", "height": "2", "palette": "#000000|#5eead4", "transparent": "0"], payload: "0,1,1,0"))
        scene.apply(command("sprite", ["id": "enemy1", "image": "enemy", "x": "10", "y": "10", "layer": "2"]))
        scene.apply(command("sprite", ["id": "enemy2", "image": "enemy", "x": "20", "y": "10", "layer": "2"]))
        scene.apply(command("sprite", ["id": "player1", "image": "player", "x": "30", "y": "10", "layer": "3"]))

        scene.apply(command("spriteRemove", ["id": "enemy"]))

        #expect(scene.spriteAsset(id: "enemy") == nil)
        #expect(scene.indexedSpriteAsset(id: "player") != nil)
        #expect(scene.primitives.map(\.id).sorted() == ["background", "player1"])
        #expect(scene.layersByID["enemy1"] == nil)
        #expect(scene.layersByID["enemy2"] == nil)
        #expect(scene.layersByID["player1"] == 3)

        scene.apply(command("spriteClear"))

        #expect(scene.spriteAssets.isEmpty)
        #expect(scene.vectorSpriteAssets.isEmpty)
        #expect(scene.indexedSpriteAssets.isEmpty)
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
