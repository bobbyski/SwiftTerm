import Foundation
import Testing

@testable import SwiftTerm

final class VTGGraphicsSceneViewportTests {
    @Test func viewportModeStoresFixedResolutionOverlayStateOnly() {
        let scene = VTGGraphicsScene()

        scene.apply(command("viewportMode", ["layer": "0", "width": "320", "height": "200", "scale": "fit"]))
        #expect(scene.viewportMode(for: 0) == nil)

        scene.apply(command("viewportMode", ["layer": "2", "width": "320", "height": "200", "scale": "integer"]))
        #expect(scene.viewportMode(for: 2) == VTGViewportMode(layer: 2, width: 320, height: 200, scaleMode: .integer))

        scene.apply(command("viewportMode", ["layer": "2", "width": "0", "height": "200", "scale": "fit"]))
        #expect(scene.viewportMode(for: 2)?.scaleMode == .integer)

        scene.apply(command("viewportMode", ["layer": "2", "value": "native"]))
        #expect(scene.viewportMode(for: 2) == nil)
    }

    @Test func viewportScaleRequiresFixedViewportAndClearsWithMode() {
        let scene = VTGGraphicsScene()

        scene.apply(command("viewportScale", ["layer": "3", "scale": "2", "x": "10", "y": "20"]))
        #expect(scene.viewportScale(for: 3) == nil)

        scene.apply(command("viewportMode", ["layer": "3", "width": "640", "height": "400", "scale": "fit"]))
        scene.apply(command("viewportScale", ["layer": "3", "scale": "2", "x": "10", "y": "20"]))
        #expect(scene.viewportScale(for: 3) == VTGViewportScale(layer: 3, scale: 2, x: 10, y: 20))

        scene.apply(command("viewportScale", ["layer": "3", "scale": "-1", "x": "40", "y": "50"]))
        #expect(scene.viewportScale(for: 3)?.scale == 2)

        scene.apply(command("viewportMode", ["layer": "3", "mode": "native"]))
        #expect(scene.viewportMode(for: 3) == nil)
        #expect(scene.viewportScale(for: 3) == nil)
    }

    @Test func viewportTransformResolvesFitIntegerStretchAndOverrides() {
        let scene = VTGGraphicsScene()

        scene.apply(command("viewportMode", ["layer": "1", "width": "320", "height": "200", "scale": "fit"]))
        #expect(scene.viewportTransform(for: 1, canvasWidth: 800, canvasHeight: 600) == VTGViewportTransform(x: 0, y: 50, scaleX: 2.5, scaleY: 2.5, width: 800, height: 500))

        scene.apply(command("viewportMode", ["layer": "1", "width": "320", "height": "200", "scale": "integer"]))
        #expect(scene.viewportTransform(for: 1, canvasWidth: 800, canvasHeight: 600) == VTGViewportTransform(x: 80, y: 100, scaleX: 2, scaleY: 2, width: 640, height: 400))

        scene.apply(command("viewportMode", ["layer": "1", "width": "320", "height": "200", "scale": "stretch"]))
        #expect(scene.viewportTransform(for: 1, canvasWidth: 800, canvasHeight: 600) == VTGViewportTransform(x: 0, y: 0, scaleX: 2.5, scaleY: 3, width: 800, height: 600))

        scene.apply(command("viewportScale", ["layer": "1", "scale": "1.5", "x": "20", "y": "30"]))
        #expect(scene.viewportTransform(for: 1, canvasWidth: 800, canvasHeight: 600) == VTGViewportTransform(x: 20, y: 30, scaleX: 1.5, scaleY: 1.5, width: 480, height: 300))
    }

    @Test func viewportMousePositionAndHitRegionsMapToVirtualCoordinates() {
        let scene = VTGGraphicsScene()

        scene.apply(command("viewportMode", ["layer": "4", "width": "320", "height": "200", "scale": "integer"]))
        scene.apply(command("viewportScale", ["layer": "4", "scale": "2", "x": "40", "y": "50"]))
        scene.apply(command("layerScroll", ["layer": "4", "x": "10", "y": "5"]))
        scene.apply(command("hit", ["id": "virtualButton", "layer": "4", "x": "20", "y": "30", "w": "40", "h": "20"]))

        let virtual = scene.viewportMousePosition(at: VTGPoint(x: 100, y: 120), canvasWidth: 800, canvasHeight: 600)
        #expect(virtual == VTGViewportMousePosition(layer: 4, x: 20, y: 30))
        #expect(scene.hitRegion(at: VTGPoint(x: 100, y: 120), canvasWidth: 800, canvasHeight: 600)?.id == "virtualButton")
        #expect(scene.hitRegion(at: VTGPoint(x: 100, y: 120)) == nil)
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
