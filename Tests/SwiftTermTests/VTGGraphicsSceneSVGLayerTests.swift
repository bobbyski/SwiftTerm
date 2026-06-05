import Foundation
import Testing

@testable import SwiftTerm

final class VTGGraphicsSceneSVGLayerTests {
    @Test func exportsLayerOffsetAndClipWrappers() {
        let scene = VTGGraphicsScene()

        scene.apply(command("layerScroll", ["layer": "2", "x": "10", "y": "20"]))
        scene.apply(command("layerAlpha", ["layer": "2", "alpha": "0.5"]))
        scene.apply(command("clip", ["layer": "2", "x": "1", "y": "2", "w": "30", "h": "40"]))
        scene.apply(command("rect", [
            "id": "box",
            "layer": "2",
            "x": "4",
            "y": "5",
            "w": "6",
            "h": "7",
            "fill": "#3b82f6"
        ]))

        let svg = scene.makeSVGFragment()

        #expect(svg.contains("<defs>"))
        #expect(svg.contains("<clipPath id=\"vtg-layer-2-clip-0\">"))
        #expect(svg.contains("transform=\"translate(10 20)\""))
        #expect(svg.contains("clip-path=\"url(#vtg-layer-2-clip-0)\""))
        #expect(svg.contains("opacity=\"0.500\""))
        #expect(svg.contains("fill=\"#3B82F6\""))
    }

    @Test func exportsViewportTransformWhenCanvasIsProvided() {
        let scene = VTGGraphicsScene()

        scene.apply(command("viewportMode", [
            "layer": "4",
            "width": "320",
            "height": "200",
            "scale": "integer"
        ]))
        scene.apply(command("line", [
            "id": "axis",
            "layer": "4",
            "x1": "0",
            "y1": "0",
            "x2": "320",
            "y2": "200",
            "stroke": "#22c55e",
            "width": "2"
        ]))

        let svg = scene.makeSVGFragment(canvasWidth: 1000, canvasHeight: 700)

        #expect(svg.contains("<clipPath id=\"vtg-layer-4-viewport-0\">"))
        #expect(svg.contains("<rect x=\"20\" y=\"50\" width=\"960\" height=\"600\""))
        #expect(svg.contains("transform=\"translate(20 50) scale(3 3)\""))
        #expect(svg.contains("<line x1=\"0\" y1=\"0\" x2=\"320\" y2=\"200\""))
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
