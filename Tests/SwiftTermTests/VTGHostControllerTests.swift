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
