import Foundation
import Testing

@testable import SwiftTerm

final class VTGGraphicsSceneSpriteTests {
    @Test func indexedSpriteUploadSharesSpritePlacementAndTransforms() {
        let scene = VTGGraphicsScene()

        scene.apply(command(
            "spriteDataUpload",
            ["id": "basicship", "width": "3", "height": "2", "palette": "#000000|#5eead4", "transparent": "0"],
            payload: "0,1,0,1,1,1"
        ))
        scene.apply(command("sprite", ["id": "ship1", "image": "basicship", "x": "10", "y": "20", "rotation": "5", "scale": "2"]))

        #expect(scene.indexedSpriteAsset(id: "basicship")?.width == 3)
        #expect(scene.primitives.count == 1)
        guard case .sprite(_, let assetID, let x, let y, let rotation, let scale, _, _) = scene.primitives[0] else {
            Issue.record("Expected retained indexed sprite instance")
            return
        }
        #expect(assetID == "basicship")
        #expect(x == 10)
        #expect(y == 20)
        #expect(rotation == 5)
        #expect(scale == 2)
    }

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
