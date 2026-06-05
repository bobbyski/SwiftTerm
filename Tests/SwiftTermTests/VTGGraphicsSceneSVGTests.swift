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
