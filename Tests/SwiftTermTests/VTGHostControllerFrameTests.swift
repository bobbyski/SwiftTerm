import Foundation
import Testing

@testable import SwiftTerm

final class VTGHostControllerFrameTests {
    @Test func offscreenFrameBuffersGraphicsUntilCommit() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 640, height: 480)

        let responses = controller.process([
            command("line", ["id": "visible", "x1": "0", "y1": "0", "x2": "10", "y2": "10"]),
            command("startFrame", ["id": "frame1", "timeout": "500"]),
            command("clear"),
            command("rect", ["id": "pending", "x": "1", "y": "2", "w": "30", "h": "40"]),
        ], canvas: canvas)

        #expect(responses == ["\u{1B}_VTG;frameStarted,id=frame1,timeout=500\u{1B}\\"])
        #expect(controller.hasPendingFrame)
        #expect(controller.pendingFrameID == "frame1")
        #expect(controller.scene.primitives.map(\.id) == ["visible"])

        let commitResponses = controller.process([command("endFrame", ["id": "frame1"])], canvas: canvas)

        #expect(commitResponses == ["\u{1B}_VTG;frameCommitted,id=frame1\u{1B}\\"])
        #expect(!controller.hasPendingFrame)
        #expect(controller.scene.primitives.map(\.id) == ["pending"])
    }

    @Test func offscreenFrameCancelDiscardsPendingGraphics() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 640, height: 480)

        let responses = controller.process([
            command("line", ["id": "visible", "x1": "0", "y1": "0", "x2": "10", "y2": "10"]),
            command("startFrame", ["id": "frame1"]),
            command("rect", ["id": "pending", "x": "1", "y": "2", "w": "30", "h": "40"]),
            command("cancelFrame", ["id": "frame1"])
        ], canvas: canvas)

        #expect(responses == [
            "\u{1B}_VTG;frameStarted,id=frame1,timeout=250\u{1B}\\",
            "\u{1B}_VTG;frameCanceled,id=frame1,reason=app\u{1B}\\"
        ])
        #expect(!controller.hasPendingFrame)
        #expect(controller.scene.primitives.map(\.id) == ["visible"])
    }

    @Test func offscreenFrameTimeoutRestoresLiveSceneBeforeNextCommand() {
        var currentDate = Date(timeIntervalSince1970: 0)
        let controller = VTGHostController(now: { currentDate })
        let canvas = VTGCanvasSize(width: 640, height: 480)

        _ = controller.process([
            command("startFrame", ["id": "frame1", "timeout": "10"]),
            command("rect", ["id": "pending", "x": "1", "y": "2", "w": "30", "h": "40"]),
        ], canvas: canvas)

        #expect(controller.hasPendingFrame)

        currentDate = Date(timeIntervalSince1970: 1)
        let timeoutResponses = controller.process([
            command("line", ["id": "visible", "x1": "0", "y1": "0", "x2": "10", "y2": "10"])
        ], canvas: canvas)

        #expect(timeoutResponses == ["\u{1B}_VTG;frameTimeout,id=frame1,reason=timeout\u{1B}\\"])
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
