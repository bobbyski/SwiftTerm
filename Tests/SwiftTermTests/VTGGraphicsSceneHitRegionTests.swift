import Foundation
import Testing

@testable import SwiftTerm

final class VTGGraphicsSceneHitRegionTests {
    @Test func hitRegionsPreferTopmostLayerAndRespectClip() {
        let scene = VTGGraphicsScene()

        scene.apply(command("clip", ["layer": "2", "x": "0", "y": "0", "w": "50", "h": "50"]))
        scene.apply(command("hit", ["id": "back", "layer": "1", "x": "0", "y": "0", "w": "100", "h": "100"]))
        scene.apply(command("hit", ["id": "front", "layer": "2", "x": "0", "y": "0", "w": "100", "h": "100"]))

        #expect(scene.hitRegion(at: VTGPoint(x: 25, y: 25))?.id == "front")
        #expect(scene.hitRegion(at: VTGPoint(x: 75, y: 75))?.id == "back")
    }

    @Test func hitClearRemovesByIDLayerOrAll() {
        let scene = VTGGraphicsScene()

        scene.apply(command("hit", ["id": "one", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("hit", ["id": "two", "layer": "2", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("hit", ["id": "three", "layer": "2", "x": "20", "y": "0", "w": "10", "h": "10"]))

        scene.apply(command("hitClear", ["id": "one"]))
        #expect(scene.hitRegions.keys.sorted() == ["three", "two"])

        scene.apply(command("hitClear", ["layer": "2"]))
        #expect(scene.hitRegions.isEmpty)

        scene.apply(command("hit", ["id": "four", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("hit", ["id": "five", "layer": "3", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("hitClear"))
        #expect(scene.hitRegions.isEmpty)
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
