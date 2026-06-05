import Foundation
import Testing

@testable import SwiftTerm

final class VTGHostControllerFrameSceneTests {
    @Test func mouseHitTestingUsesVisibleSceneWhileFrameIsPending() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 640, height: 480)
        let snapshot = VTGMouseSnapshot(x: 20, y: 20, cellX: 2, cellY: 2, modifiers: "none")

        _ = controller.process([
            command("mouseEvents", ["enabled": "1", "mode": "click"]),
            command("hit", ["id": "visible", "target": "visibleButton", "x": "0", "y": "0", "w": "80", "h": "80"]),
            command("startFrame", ["id": "frame1"]),
            command("hitClear"),
            command("hit", ["id": "pending", "target": "pendingButton", "x": "0", "y": "0", "w": "80", "h": "80"])
        ], canvas: canvas)

        let pendingClick = controller.mouseResponse(type: .click, button: 0, snapshot: snapshot)

        #expect(pendingClick?.contains("hit=visible") == true)
        #expect(pendingClick?.contains("target=visibleButton") == true)
        #expect(pendingClick?.contains("pending") == false)

        _ = controller.process([command("endFrame", ["id": "frame1"])], canvas: canvas)

        let committedClick = controller.mouseResponse(type: .click, button: 0, snapshot: snapshot)

        #expect(committedClick?.contains("hit=pending") == true)
        #expect(committedClick?.contains("target=pendingButton") == true)
    }

    @Test func discardPendingFrameLeavesVisibleSceneUnchanged() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 640, height: 480)

        _ = controller.process([
            command("line", ["id": "visible", "x1": "0", "y1": "0", "x2": "10", "y2": "10"]),
            command("startFrame", ["id": "frame1"]),
            command("clear"),
            command("rect", ["id": "pending", "x": "1", "y": "2", "w": "30", "h": "40"])
        ], canvas: canvas)

        controller.discardPendingFrame()

        #expect(!controller.hasPendingFrame)
        #expect(controller.scene.primitives.map(\.id) == ["visible"])
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
