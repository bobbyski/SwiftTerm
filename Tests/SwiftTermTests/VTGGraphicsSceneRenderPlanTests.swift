import Foundation
import Testing

@testable import SwiftTerm

final class VTGGraphicsSceneRenderPlanTests {
    @Test func renderPlanResolvesOrderAndPlaneFiltering() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", ["id": "under", "layer": "-1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("rect", ["id": "overlay1", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("rect", ["id": "text0", "layer": "0", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("rect", ["id": "overlay4", "layer": "4", "x": "0", "y": "0", "w": "10", "h": "10"]))

        let all = scene.renderPlan(canvas: VTGRenderCanvas(width: 800, height: 600))
        #expect(all.entries.map(\.primitive.id) == ["under", "text0", "overlay1", "overlay4"])
        #expect(all.entries.map(\.layer) == [-1, 0, 1, 4])

        let underText = scene.renderPlan(plane: .underText, canvas: VTGRenderCanvas(width: 800, height: 600))
        #expect(underText.entries.map(\.primitive.id) == ["under"])
        #expect(underText.plane == .underText)

        let textPlane = scene.renderPlan(plane: .textPlane, canvas: VTGRenderCanvas(width: 800, height: 600))
        #expect(textPlane.entries.map(\.primitive.id) == ["text0"])
        #expect(textPlane.plane == .textPlane)

        let overlay = scene.renderPlan(plane: .overlay, canvas: VTGRenderCanvas(width: 800, height: 600))
        #expect(overlay.entries.map(\.primitive.id) == ["overlay1", "overlay4"])
        #expect(overlay.plane == .overlay)
    }

    @Test func renderPlanIncludesLayerAlphaScrollAndClip() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", ["id": "panel", "layer": "3", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("layerAlpha", ["layer": "3", "alpha": "0.5"]))
        scene.apply(command("layerScroll", ["layer": "3", "x": "12", "y": "-8"]))
        scene.apply(command("clip", ["layer": "3", "x": "4", "y": "5", "w": "100", "h": "60"]))

        let entry = scene.renderPlan(plane: .overlay, canvas: VTGRenderCanvas(width: 800, height: 600)).entries[0]

        #expect(entry.primitive.id == "panel")
        #expect(entry.layer == 3)
        #expect(entry.alpha == 0.5)
        #expect(entry.offset == VTGLayerOffset(x: 12, y: -8))
        #expect(entry.clip == VTGLayerClip(x: 4, y: 5, width: 100, height: 60))
        #expect(entry.viewport == nil)
    }

    @Test func underTextRenderPlanIncludesClip() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", ["id": "native-under", "layer": "-1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("clip", ["layer": "-1", "x": "20", "y": "30", "w": "120", "h": "90"]))

        let entry = scene.renderPlan(
            plane: .underText,
            canvas: VTGRenderCanvas(width: 800, height: 600)
        ).entries[0]

        #expect(entry.primitive.id == "native-under")
        #expect(entry.layer == VTGLayerModel.underTextLayer)
        #expect(entry.clip == VTGLayerClip(x: 20, y: 30, width: 120, height: 90))
        #expect(entry.viewport == nil)
    }

    @Test func renderPlanIncludesFixedViewportTransform() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", ["id": "virtual", "layer": "2", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("viewportMode", ["layer": "2", "width": "320", "height": "200", "scale": "fit"]))

        let entry = scene.renderPlan(plane: .overlay, canvas: VTGRenderCanvas(width: 640, height: 480)).entries[0]

        #expect(entry.viewport == VTGViewportTransform(
            x: 0,
            y: 40,
            scaleX: 2,
            scaleY: 2,
            width: 640,
            height: 400
        ))
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
