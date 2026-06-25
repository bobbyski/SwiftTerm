import Foundation
import Testing

@testable import SwiftTerm

final class VTGGraphicsSceneShapeTests {
    @Test func clearRectRemovesPrimitivesTouchingRegion() {
        let scene = VTGGraphicsScene()

        scene.apply(command("draw", ["id": "clock-text-0-0", "stroke": "#5eead4", "width": "2"], payload: "10,10 40,10 40,40"))
        scene.apply(command("draw", ["id": "clock-text-1-0", "stroke": "#facc15", "width": "2"], payload: "50,10 70,10 70,40"))
        scene.apply(command("draw", ["id": "outside", "stroke": "#ffffff", "width": "2"], payload: "160,10 180,10"))

        scene.apply(command("clearRect", [
            "id": "erase",
            "x": "35",
            "y": "8",
            "w": "40",
            "h": "40"
        ]))

        #expect(scene.primitives.map(\.id) == ["outside"])
    }

    @Test func clearRectOnlyRemovesTargetLayer() {
        let scene = VTGGraphicsScene()

        scene.apply(command("draw", ["id": "overlay1", "layer": "1", "stroke": "#5eead4", "width": "2"], payload: "10,10 40,10"))
        scene.apply(command("draw", ["id": "overlay2", "layer": "2", "stroke": "#facc15", "width": "2"], payload: "10,10 40,10"))

        scene.apply(command("clearRect", [
            "id": "erase",
            "layer": "1",
            "x": "0",
            "y": "0",
            "w": "80",
            "h": "80"
        ]))

        #expect(scene.primitives.map(\.id) == ["overlay2"])
        #expect(scene.layer(for: scene.primitives[0]) == 2)
    }

    @Test func rectParsesOptionalCornerRadius() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", [
            "id": "rounded",
            "x": "10",
            "y": "20",
            "w": "30",
            "h": "40",
            "radius": "8",
            "corners": "12421"
        ]))

        guard case .rect(_, _, _, _, _, let radius, let corners, _, _, _, _) = scene.primitives.first else {
            Issue.record("Expected retained rect primitive")
            return
        }
        #expect(radius == 8)
        #expect(corners == "124")
    }

    @Test func triangleParsesOptionalCornerRadius() {
        let scene = VTGGraphicsScene()

        scene.apply(command("triangle", [
            "id": "rounded-triangle",
            "x1": "10",
            "y1": "80",
            "x2": "90",
            "y2": "80",
            "x3": "50",
            "y3": "10",
            "radius": "12"
        ]))

        guard case .triangle(_, _, _, _, let radius, _, _, _, _) = scene.primitives.first else {
            Issue.record("Expected retained triangle primitive")
            return
        }
        #expect(radius == 12)
    }

    @Test func parsesOptionalStrokePaintStyle() {
        let scene = VTGGraphicsScene()

        scene.apply(command("draw", [
            "id": "styled",
            "stroke": "#22c55e",
            "width": "4",
            "lineCap": "square",
            "lineJoin": "bevel"
        ], payload: "0,0 10,10 20,0"))

        guard case .draw(_, _, _, _, let lineCap, let lineJoin) = scene.primitives.first else {
            Issue.record("Expected retained draw primitive")
            return
        }
        #expect(lineCap == .square)
        #expect(lineJoin == .bevel)
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
