import Foundation
import Testing

@testable import SwiftTerm

final class VTGGraphicsSceneTests {
    @Test func retainsAndReplacesPrimitiveByID() {
        let scene = VTGGraphicsScene()

        scene.apply(command("line", [
            "id": "axis",
            "x1": "0",
            "y1": "0",
            "x2": "10",
            "y2": "10",
            "stroke": "#22c55e",
            "width": "2"
        ]))
        scene.apply(command("line", [
            "id": "axis",
            "x1": "0",
            "y1": "0",
            "x2": "20",
            "y2": "20",
            "stroke": "#22c55e",
            "width": "4"
        ]))

        #expect(scene.primitives.count == 1)
        guard case .line(_, _, _, let x2, let y2, _, let width) = scene.primitives.first else {
            Issue.record("Expected retained line primitive")
            return
        }
        #expect(x2 == 20)
        #expect(y2 == 20)
        #expect(width == 4)
    }

    @Test func renderPrimitivesAreSortedByLayerThenInsertionOrder() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", ["id": "front", "layer": "3", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("rect", ["id": "back", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("rect", ["id": "middle", "layer": "2", "x": "0", "y": "0", "w": "10", "h": "10"]))

        #expect(scene.renderPrimitives.map(\.id) == ["back", "middle", "front"])
    }

    @Test func layerCommandMovesExistingPrimitiveWithoutRedraw() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", ["id": "movable", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("layer", ["id": "movable", "value": "4"]))

        #expect(scene.primitives.count == 1)
        #expect(scene.layer(for: scene.primitives[0]) == VTGLayerModel.lastOverlayLayer)
    }

    @Test func layerCommandIgnoresUnknownPrimitiveIDs() {
        let scene = VTGGraphicsScene()

        scene.apply(command("layer", ["id": "missing", "value": "4"]))

        #expect(scene.layersByID.isEmpty)
        #expect(scene.primitives.isEmpty)
    }

    @Test func hitRegionsPreferTopmostLayerAndRespectClip() {
        let scene = VTGGraphicsScene()

        scene.apply(command("clip", ["layer": "2", "x": "0", "y": "0", "w": "50", "h": "50"]))
        scene.apply(command("hit", ["id": "back", "layer": "1", "x": "0", "y": "0", "w": "100", "h": "100"]))
        scene.apply(command("hit", ["id": "front", "layer": "2", "x": "0", "y": "0", "w": "100", "h": "100"]))

        #expect(scene.hitRegion(at: VTGPoint(x: 25, y: 25))?.id == "front")
        #expect(scene.hitRegion(at: VTGPoint(x: 75, y: 75))?.id == "back")
    }

    @Test func layerModelClampsDrawingLayersAndReservesTextPlaneFromScrolling() {
        let scene = VTGGraphicsScene()

        scene.apply(command("defaultLayer", ["value": "-2"]))
        #expect(scene.defaultLayer == VTGLayerModel.textPlaneLayer)

        scene.apply(command("rect", ["id": "textPlane", "x": "0", "y": "0", "w": "10", "h": "10"]))
        #expect(scene.layer(for: scene.primitives[0]) == VTGLayerModel.textPlaneLayer)

        scene.apply(command("defaultLayer", ["value": "99"]))
        #expect(scene.defaultLayer == VTGLayerModel.lastOverlayLayer)

        scene.apply(command("layerScroll", ["layer": "0", "x": "10", "y": "20"]))
        #expect(scene.offset(for: VTGLayerModel.textPlaneLayer) == .zero)

        scene.apply(command("layerScroll", ["layer": "4", "x": "10", "y": "20"]))
        #expect(scene.offset(for: VTGLayerModel.lastOverlayLayer) == VTGLayerOffset(x: 10, y: 20))
    }

    @Test func layerAlphaAppliesOnlyToOverlayLayersAndClampsValues() {
        let scene = VTGGraphicsScene()

        scene.apply(command("layerAlpha", ["layer": "0", "alpha": "0.25"]))
        #expect(scene.alpha(for: VTGLayerModel.textPlaneLayer) == 1)

        scene.apply(command("layerAlpha", ["layer": "3", "alpha": "0.45"]))
        #expect(scene.alpha(for: 3) == 0.45)

        scene.apply(command("layerAlpha", ["layer": "3", "alpha": "2"]))
        #expect(scene.alpha(for: 3) == 1)

        scene.apply(command("layerAlpha", ["layer": "3", "alpha": "-1"]))
        #expect(scene.alpha(for: 3) == 0)
    }

    @Test func vectorSpriteUploadSharesSpritePlacementAndTransforms() {
        let scene = VTGGraphicsScene()

        scene.apply(command(
            "vectorSpriteUpload",
            ["id": "ship", "width": "40", "height": "30", "stroke": "#5eead4", "fill": "#07111d", "lineWidth": "2"],
            payload: "M 20 0 L 40 30 L 20 22 L 0 30 Z"
        ))
        scene.apply(command("sprite", ["id": "ship1", "image": "ship", "x": "10", "y": "20", "rotation": "5", "scale": "1.5"]))
        scene.apply(command("spriteTransform", ["id": "ship1", "x": "30", "y": "40", "rotation": "15", "scale": "2"]))

        #expect(scene.vectorSpriteAsset(id: "ship")?.width == 40)
        #expect(scene.primitives.count == 1)
        guard case .sprite(_, let assetID, let x, let y, let rotation, let scale) = scene.primitives[0] else {
            Issue.record("Expected retained vector sprite instance")
            return
        }
        #expect(assetID == "ship")
        #expect(x == 30)
        #expect(y == 40)
        #expect(rotation == 15)
        #expect(scale == 2)
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
