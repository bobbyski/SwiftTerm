import Foundation
import Testing

@testable import SwiftTerm

final class VTGGraphicsSceneLayerTests {
    @Test func layerCommandMovesExistingPrimitiveWithoutRedraw() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", ["id": "movable", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("layer", ["id": "movable", "layer": "4"]))

        #expect(scene.primitives.count == 1)
        #expect(scene.layer(for: scene.primitives[0]) == VTGLayerModel.lastOverlayLayer)
    }

    @Test func defaultLayerAndObjectLayerAcceptCanonicalLayerParameter() {
        let scene = VTGGraphicsScene()

        scene.apply(command("defaultLayer", ["layer": "2"]))
        scene.apply(command("rect", ["id": "pane", "x": "0", "y": "0", "w": "10", "h": "10"]))
        #expect(scene.layer(for: scene.primitives[0]) == 2)

        scene.apply(command("layer", ["id": "pane", "layer": "3"]))
        #expect(scene.layer(for: scene.primitives[0]) == 3)

        scene.apply(command("rect", ["id": "pane", "x": "0", "y": "0", "w": "20", "h": "20"]))
        #expect(scene.primitives.count == 1)
        #expect(scene.layer(for: scene.primitives[0]) == 3)
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

    @Test func hitClearRemovesByIDLayerOrAll() {
        let scene = VTGGraphicsScene()

        scene.apply(command("hit", ["id": "one", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("hit", ["id": "two", "layer": "2", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("hit", ["id": "three", "layer": "2", "x": "20", "y": "0", "w": "10", "h": "10"]))

        scene.apply(command("hitClear", ["id": "one"]))
        #expect(scene.hitRegions.keys.sorted() == ["three", "two"])

        scene.apply(command("hitClear", ["layer": "2"]))
        #expect(scene.hitRegions.isEmpty)

        scene.apply(command("hit", ["id": "four", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("hit", ["id": "five", "layer": "3", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("hitClear"))
        #expect(scene.hitRegions.isEmpty)
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

    @Test func layerClipCanBeSetClearedAndIgnoresInvalidSizes() {
        let scene = VTGGraphicsScene()

        scene.apply(command("clip", ["layer": "2", "x": "10", "y": "20", "w": "100", "h": "50"]))
        #expect(scene.clip(for: 2) == VTGLayerClip(x: 10, y: 20, width: 100, height: 50))

        scene.apply(command("clip", ["layer": "3", "x": "0", "y": "0", "w": "0", "h": "50"]))
        #expect(scene.clip(for: 3) == nil)

        scene.apply(command("clipClear", ["layer": "2"]))
        #expect(scene.clip(for: 2) == nil)
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
