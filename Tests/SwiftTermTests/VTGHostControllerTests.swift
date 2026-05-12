import Foundation
import Testing

@testable import SwiftTerm

final class VTGHostControllerTests {
    @Test func handlesCapabilitiesAndAppliesSceneCommand() {
        let controller = VTGHostController()
        let responses = controller.process(
            [
                command("capabilities?"),
                command("line", [
                    "id": "axis",
                    "x1": "1",
                    "y1": "2",
                    "x2": "3",
                    "y2": "4"
                ])
            ],
            canvas: VTGCanvasSize(width: 640, height: 480)
        )

        #expect(responses.count == 1)
        #expect(responses.first?.contains("_VTG;capabilities") == true)
        #expect(controller.scene.primitives.count == 1)
    }

    @Test func resizeResponsesHonorSubscriptionAndDeduplicate() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 100, height: 80)

        #expect(controller.resizeResponseIfNeeded(canvas: canvas) == nil)

        _ = controller.process([command("resizeEvents", ["enabled": "1"])], canvas: canvas)

        #expect(controller.resizeResponseIfNeeded(canvas: canvas) == nil)
        #expect(controller.resizeResponseIfNeeded(canvas: canvas, force: true) != nil)
        #expect(controller.resizeResponseIfNeeded(canvas: VTGCanvasSize(width: 120, height: 80)) != nil)
    }

    @Test func mouseResponseUsesModeAndHitRegion() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 100, height: 100)

        _ = controller.process([
            command("mouseEvents", ["enabled": "1", "mode": "click"]),
            command("hit", ["id": "quit", "target": "button", "x": "0", "y": "0", "w": "50", "h": "50"])
        ], canvas: canvas)

        let snapshot = VTGMouseSnapshot(x: 10, y: 10, cellX: 1, cellY: 1, modifiers: "none")

        #expect(controller.mouseResponse(type: "down", button: 0, snapshot: snapshot) == nil)
        let click = controller.mouseResponse(type: "click", button: 0, snapshot: snapshot)
        #expect(click?.contains("hit=quit") == true)
        #expect(click?.contains("target=button") == true)
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
