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
        guard case .line(_, _, _, let x2, let y2, _, let width, _) = scene.primitives.first else {
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
