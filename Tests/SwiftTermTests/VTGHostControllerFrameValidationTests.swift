import Foundation
import Testing

@testable import SwiftTerm

final class VTGHostControllerFrameValidationTests {
    @Test func offscreenFrameEndRequiresMatchingID() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 640, height: 480)

        let mismatchResponses = controller.process([
            command("startFrame", ["id": "frame1"]),
            command("rect", ["id": "pending", "x": "1", "y": "2", "w": "30", "h": "40"]),
            command("endFrame", ["id": "wrong"])
        ], canvas: canvas)

        #expect(mismatchResponses == [
            "\u{1B}_VTG;frameStarted,id=frame1,timeout=250\u{1B}\\",
            "\u{1B}_VTG;frameRejected,id=wrong,reason=idMismatch\u{1B}\\"
        ])
        #expect(controller.hasPendingFrame)
        #expect(controller.scene.primitives.isEmpty)

        _ = controller.process([command("endFrame", ["id": "frame1"])], canvas: canvas)

        #expect(!controller.hasPendingFrame)
        #expect(controller.scene.primitives.map(\.id) == ["pending"])
    }

    @Test func offscreenFrameCancelRequiresMatchingID() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 640, height: 480)

        let mismatchResponses = controller.process([
            command("line", ["id": "visible", "x1": "0", "y1": "0", "x2": "10", "y2": "10"]),
            command("startFrame", ["id": "frame1"]),
            command("clear"),
            command("cancelFrame", ["id": "wrong"])
        ], canvas: canvas)

        #expect(mismatchResponses == [
            "\u{1B}_VTG;frameStarted,id=frame1,timeout=250\u{1B}\\",
            "\u{1B}_VTG;frameRejected,id=wrong,reason=idMismatch\u{1B}\\"
        ])
        #expect(controller.hasPendingFrame)
        #expect(controller.scene.primitives.map(\.id) == ["visible"])

        let cancelResponses = controller.process([command("cancelFrame", ["id": "frame1"])], canvas: canvas)

        #expect(cancelResponses == ["\u{1B}_VTG;frameCanceled,id=frame1,reason=app\u{1B}\\"])
        #expect(!controller.hasPendingFrame)
        #expect(controller.scene.primitives.map(\.id) == ["visible"])
    }

    @Test func offscreenFrameStartRejectsNestedFrame() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 640, height: 480)

        let responses = controller.process([
            command("startFrame", ["id": "frame1"]),
            command("rect", ["id": "pending", "x": "1", "y": "2", "w": "30", "h": "40"]),
            command("startFrame", ["id": "frame2"])
        ], canvas: canvas)

        #expect(responses == [
            "\u{1B}_VTG;frameStarted,id=frame1,timeout=250\u{1B}\\",
            "\u{1B}_VTG;frameRejected,id=frame2,reason=nested\u{1B}\\"
        ])
        #expect(controller.hasPendingFrame)
        #expect(controller.pendingFrameID == "frame1")

        let commitResponses = controller.process([command("endFrame", ["id": "frame1"])], canvas: canvas)

        #expect(commitResponses == ["\u{1B}_VTG;frameCommitted,id=frame1\u{1B}\\"])
        #expect(controller.scene.primitives.map(\.id) == ["pending"])
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
