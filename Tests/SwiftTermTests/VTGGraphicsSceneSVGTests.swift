import Foundation
import Testing

@testable import SwiftTerm

final class VTGGraphicsSceneSVGTests {
    @Test func exportsBasicPrimitivesAndEscapesText() {
        let scene = VTGGraphicsScene()

        scene.apply(command("line", [
            "id": "axis",
            "x1": "1",
            "y1": "2",
            "x2": "3",
            "y2": "4",
            "stroke": "#22c55e",
            "width": "2"
        ]))
        scene.apply(command("text", [
            "id": "label",
            "x": "10",
            "y": "20",
            "color": "#ffffff",
            "size": "12"
        ], payload: "A&B <tag>"))

        let svg = scene.makeSVGFragment()

        #expect(svg.contains("<line x1=\"1\" y1=\"2\" x2=\"3\" y2=\"4\""))
        #expect(svg.contains("stroke=\"#22C55E\""))
        #expect(svg.contains("A&amp;B &lt;tag&gt;"))
    }

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
