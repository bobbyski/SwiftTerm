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
        scene.apply(command("rect", [
            "id": "rounded",
            "x": "20",
            "y": "30",
            "w": "40",
            "h": "50",
            "radius": "9",
            "stroke": "#5eead4"
        ]))
        scene.apply(command("triangle", [
            "id": "rounded-triangle",
            "x1": "10",
            "y1": "90",
            "x2": "90",
            "y2": "90",
            "x3": "50",
            "y3": "10",
            "radius": "12",
            "fill": "#3b82f6"
        ]))

        let svg = scene.makeSVGFragment()

        #expect(svg.contains("<line x1=\"1\" y1=\"2\" x2=\"3\" y2=\"4\""))
        #expect(svg.contains("stroke=\"#22C55E\""))
        #expect(svg.contains("<rect x=\"20\" y=\"30\" width=\"40\" height=\"50\" rx=\"9\" ry=\"9\""))
        #expect(svg.contains("<path d=\"M "))
        #expect(svg.contains("Q 90 90"))
        #expect(svg.contains("fill=\"#3B82F6\""))
        #expect(svg.contains("A&amp;B &lt;tag&gt;"))
    }

    @Test func exportsSelectiveRoundedRectAsPath() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", [
            "id": "top-rounded",
            "x": "20",
            "y": "30",
            "w": "40",
            "h": "50",
            "radius": "9",
            "corners": "12",
            "stroke": "#5eead4"
        ]))

        let svg = scene.makeSVGFragment()

        #expect(svg.contains("<path d=\"M 29 30 L 51 30 Q 60 30 60 39"))
        #expect(svg.contains("L 60 80"))
        #expect(svg.contains("L 20 80"))
        #expect(svg.contains("Q 20 30 29 30"))
        #expect(!svg.contains("rx=\"9\""))
    }

    @Test func exportsStrokePaintStyleAttributes() {
        let scene = VTGGraphicsScene()

        scene.apply(command("path", [
            "id": "styled-path",
            "stroke": "#22c55e",
            "width": "5",
            "lineCap": "square",
            "lineJoin": "bevel"
        ], payload: "M 0 0 L 10 10 L 20 0"))

        let svg = scene.makeSVGFragment()

        #expect(svg.contains("stroke-linecap=\"square\""))
        #expect(svg.contains("stroke-linejoin=\"bevel\""))
    }

    @Test func exportsIndexedSpritePixels() {
        let scene = VTGGraphicsScene()

        scene.apply(command(
            "spriteDataUpload",
            ["id": "basicship", "width": "2", "height": "2", "palette": "#000000|#5eead4", "transparent": "0", "filter": "nearest"],
            payload: "0,1,1,0"
        ))
        scene.apply(command("sprite", ["id": "ship1", "image": "basicship", "x": "10", "y": "20", "scale": "3"]))

        let svg = scene.makeSVGFragment()

        #expect(svg.contains("data-indexed-sprite=\"basicship\""))
        #expect(svg.contains("shape-rendering=\"crispEdges\""))
        #expect(svg.contains("scale(3)"))
        #expect(svg.contains("<rect x=\"1\" y=\"0\" width=\"1\" height=\"1\" fill=\"#5EEAD4\""))
        #expect(svg.contains("<rect x=\"0\" y=\"1\" width=\"1\" height=\"1\" fill=\"#5EEAD4\""))
    }

    @Test func exportsBitmapSpriteFilterHint() {
        let scene = VTGGraphicsScene()
        let payload = Data([1]).base64EncodedString()

        scene.apply(command("spriteUpload", ["id": "pixelship", "format": "png", "width": "2", "height": "2", "filter": "nearest"], payload: payload))
        scene.apply(command("sprite", ["id": "ship1", "image": "pixelship", "x": "10", "y": "20", "scale": "3"]))

        let svg = scene.makeSVGFragment()

        #expect(svg.contains("image-rendering=\"pixelated\""))
    }

    @Test func exportsDirectImageFilterHint() {
        let scene = VTGGraphicsScene()
        let payload = Data([1, 2, 3]).base64EncodedString()

        scene.apply(command(
            "image",
            ["id": "retro", "format": "png", "x": "1", "y": "2", "width": "3", "height": "4", "filter": "nearest"],
            payload: payload
        ))

        let svg = scene.makeSVGFragment()

        #expect(svg.contains("<image x=\"1\" y=\"2\" width=\"3\" height=\"4\" image-rendering=\"pixelated\""))
        #expect(svg.contains("href=\"data:image/png;base64,\(payload)\""))
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
