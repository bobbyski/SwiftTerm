import Foundation
import Testing

@testable import SwiftTerm

final class VTGHostControllerMouseTests {
    @Test func mouseResponseUsesModeAndHitRegion() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 100, height: 100)

        _ = controller.process([
            command("mouseEvents", ["enabled": "1", "mode": "click"]),
            command("hit", ["id": "quit", "target": "button", "x": "0", "y": "0", "w": "50", "h": "50"])
        ], canvas: canvas)

        let snapshot = VTGMouseSnapshot(x: 10, y: 10, cellX: 1, cellY: 1, modifiers: "none")

        #expect(controller.mouseResponse(type: .down, button: 0, snapshot: snapshot) == nil)
        let click = controller.mouseResponse(type: .click, button: 0, snapshot: snapshot)
        #expect(click?.contains("hit=quit") == true)
        #expect(click?.contains("target=button") == true)
        #expect(controller.mouseResponse(type: "bogus", button: 0, snapshot: snapshot) == nil)
    }

    @Test func mouseResponseIncludesVirtualViewportCoordinates() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 800, height: 600)

        _ = controller.process([
            command("mouseEvents", ["enabled": "1", "mode": "click"]),
            command("viewportMode", ["layer": "4", "width": "320", "height": "200", "scale": "fit"]),
            command("viewportScale", ["layer": "4", "scale": "2", "x": "40", "y": "50"]),
            command("hit", ["id": "virtual", "target": "virtualButton", "layer": "4", "x": "20", "y": "30", "w": "40", "h": "20"])
        ], canvas: canvas)

        let snapshot = VTGMouseSnapshot(x: 80, y: 110, cellX: 8, cellY: 6, modifiers: "none")
        let response = controller.mouseResponse(type: .click, button: 0, snapshot: snapshot, canvas: canvas)

        #expect(response?.contains("viewportLayer=4") == true)
        #expect(response?.contains("virtualX=20") == true)
        #expect(response?.contains("virtualY=30") == true)
        #expect(response?.contains("hit=virtual") == true)
        #expect(response?.contains("target=virtualButton") == true)
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
