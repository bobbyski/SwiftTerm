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

    @Test func hitRegionsPreferTopmostLayerAndRespectClip() {
        let scene = VTGGraphicsScene()

        scene.apply(command("clip", ["layer": "2", "x": "0", "y": "0", "w": "50", "h": "50"]))
        scene.apply(command("hit", ["id": "back", "layer": "1", "x": "0", "y": "0", "w": "100", "h": "100"]))
        scene.apply(command("hit", ["id": "front", "layer": "2", "x": "0", "y": "0", "w": "100", "h": "100"]))

        #expect(scene.hitRegion(at: VTGPoint(x: 25, y: 25))?.id == "front")
        #expect(scene.hitRegion(at: VTGPoint(x: 75, y: 75))?.id == "back")
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
