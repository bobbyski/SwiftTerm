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

    @Test func capabilitiesResponseCanAdvertiseHostRenderer() {
        let controller = VTGHostController()
        let responses = controller.process(
            [command("capabilities?")],
            canvas: VTGCanvasSize(width: 640, height: 480),
            renderer: "metal"
        )

        #expect(responses.count == 1)
        #expect(responses.first?.contains("renderer=metal") == true)
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

    @Test func linkDetectionCommandUpdatesSettingsAndPreservesInvalidColor() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 100, height: 80)

        _ = controller.process([command("linkDetection", [
            "enabled": "0",
            "decorate": "0",
            "color": "#ff00aa"
        ])], canvas: canvas)

        #expect(!controller.linkDetectionSettings.isEnabled)
        #expect(!controller.linkDetectionSettings.decoratesLinks)
        #expect(controller.linkDetectionSettings.color == VTGColor(hex: "#ff00aa"))

        _ = controller.process([command("linkDetection", [
            "enabled": "1",
            "color": "not-a-color"
        ])], canvas: canvas)

        #expect(controller.linkDetectionSettings.isEnabled)
        #expect(!controller.linkDetectionSettings.decoratesLinks)
        #expect(controller.linkDetectionSettings.color == VTGColor(hex: "#ff00aa"))
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
