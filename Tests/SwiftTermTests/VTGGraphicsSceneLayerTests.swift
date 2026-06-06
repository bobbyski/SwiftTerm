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

    @Test func layerModelClampsDrawingLayersAndReservesSharedPlanesFromScrolling() {
        let scene = VTGGraphicsScene()

        scene.apply(command("defaultLayer", ["value": "-2"]))
        #expect(scene.defaultLayer == VTGLayerModel.underTextLayer)

        scene.apply(command("rect", ["id": "underText", "x": "0", "y": "0", "w": "10", "h": "10"]))
        #expect(scene.layer(for: scene.primitives[0]) == VTGLayerModel.underTextLayer)

        scene.apply(command("defaultLayer", ["value": "99"]))
        #expect(scene.defaultLayer == VTGLayerModel.lastOverlayLayer)

        scene.apply(command("layerScroll", ["layer": "-1", "x": "10", "y": "20"]))
        #expect(scene.offset(for: VTGLayerModel.underTextLayer) == .zero)

        scene.apply(command("layerScroll", ["layer": "0", "x": "10", "y": "20"]))
        #expect(scene.offset(for: VTGLayerModel.textPlaneLayer) == .zero)

        scene.apply(command("layerScroll", ["layer": "4", "x": "10", "y": "20"]))
        #expect(scene.offset(for: VTGLayerModel.lastOverlayLayer) == VTGLayerOffset(x: 10, y: 20))
    }

    @Test func renderPrimitivesCanBeSeparatedByCompositingPlane() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", ["id": "overlayA", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("rect", ["id": "underA", "layer": "-1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("rect", ["id": "textA", "layer": "0", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("rect", ["id": "overlayB", "layer": "3", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("rect", ["id": "textB", "layer": "0", "x": "0", "y": "0", "w": "10", "h": "10"]))

        #expect(scene.underTextPrimitives.map(\.id) == ["underA"])
        #expect(scene.textPlanePrimitives.map(\.id) == ["textA", "textB"])
        #expect(scene.overlayPrimitives.map(\.id) == ["overlayA", "overlayB"])
        #expect(scene.renderPrimitives(in: .underText).map(\.id) == ["underA"])
        #expect(scene.renderPrimitives(in: .textPlane).map(\.id) == ["textA", "textB"])
        #expect(scene.renderPrimitives(in: .overlay).map(\.id) == ["overlayA", "overlayB"])
    }

    @Test func layerModelReportsCompositingPlane() {
        #expect(VTGLayerModel.compositingPlane(for: VTGLayerModel.underTextLayer) == .underText)
        #expect(VTGLayerModel.compositingPlane(for: VTGLayerModel.textPlaneLayer) == .textPlane)
        #expect(VTGLayerModel.compositingPlane(for: VTGLayerModel.firstOverlayLayer) == .overlay)
        #expect(VTGLayerModel.compositingPlane(for: VTGLayerModel.lastOverlayLayer) == .overlay)
    }

    @Test func layerAlphaAppliesOnlyToOverlayLayersAndClampsValues() {
        let scene = VTGGraphicsScene()

        scene.apply(command("layerAlpha", ["layer": "-1", "alpha": "0.25"]))
        #expect(scene.alpha(for: VTGLayerModel.underTextLayer) == 1)

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
