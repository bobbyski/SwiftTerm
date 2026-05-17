import Foundation
import Testing
#if os(macOS)
import AppKit
#endif

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

        #expect(controller.mouseResponse(type: .down, button: 0, snapshot: snapshot) == nil)
        let click = controller.mouseResponse(type: .click, button: 0, snapshot: snapshot)
        #expect(click?.contains("hit=quit") == true)
        #expect(click?.contains("target=button") == true)
        #expect(controller.mouseResponse(type: "bogus", button: 0, snapshot: snapshot) == nil)
    }

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

    @Test func offscreenFrameEndRequiresMatchingID() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 640, height: 480)

        _ = controller.process([
            command("startFrame", ["id": "frame1"]),
            command("rect", ["id": "pending", "x": "1", "y": "2", "w": "30", "h": "40"]),
            command("endFrame", ["id": "wrong"])
        ], canvas: canvas)

        #expect(controller.hasPendingFrame)
        #expect(controller.scene.primitives.isEmpty)

        _ = controller.process([command("endFrame", ["id": "frame1"])], canvas: canvas)

        #expect(!controller.hasPendingFrame)
        #expect(controller.scene.primitives.map(\.id) == ["pending"])
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

    @Test func clickSynthesizerRequiresSameButtonAndSmallMovement() {
        let synthesizer = VTGMouseClickSynthesizer(
            maximumClickInterval: 0.5,
            maximumClickDistance: 8
        )
        let down = VTGMouseSnapshot(x: 20, y: 30, cellX: 2, cellY: 3, modifiers: "none")
        let nearby = VTGMouseSnapshot(x: 24, y: 35, cellX: 2, cellY: 3, modifiers: "none")
        let farAway = VTGMouseSnapshot(x: 60, y: 80, cellX: 6, cellY: 8, modifiers: "none")

        synthesizer.recordDown(button: 0, snapshot: down, timestamp: 10)

        #expect(synthesizer.shouldSynthesizeClick(button: 0, snapshot: nearby, timestamp: 10.2))
        #expect(!synthesizer.shouldSynthesizeClick(button: 1, snapshot: nearby, timestamp: 10.2))
        #expect(!synthesizer.shouldSynthesizeClick(button: 0, snapshot: nearby, timestamp: 11))
        #expect(!synthesizer.shouldSynthesizeClick(button: 0, snapshot: farAway, timestamp: 10.2))

        synthesizer.reset()
        #expect(!synthesizer.shouldSynthesizeClick(button: 0, snapshot: nearby, timestamp: 10.2))
    }

    @Test func coordinateMapperClampsPixelsAndMapsCells() {
        let mapper = VTGMouseCoordinateMapper(
            columns: 10,
            rows: 5,
            canvasWidth: 100,
            canvasHeight: 50
        )

        #expect(mapper.cellPosition(pixelX: 0, pixelY: 0)?.gridCol == 0)
        #expect(mapper.cellPosition(pixelX: 0, pixelY: 0)?.gridRow == 0)

        let middle = mapper.cellPosition(pixelX: 55, pixelY: 29)
        #expect(middle?.gridCol == 5)
        #expect(middle?.gridRow == 2)
        #expect(middle?.pixelX == 55)
        #expect(middle?.pixelY == 29)

        let clamped = mapper.snapshot(pixelX: 999, pixelY: -20, modifiers: "shift")
        #expect(clamped?.x == 100)
        #expect(clamped?.y == 0)
        #expect(clamped?.cellX == 10)
        #expect(clamped?.cellY == 1)
        #expect(clamped?.modifiers == "shift")
    }

    @Test func mouseModifiersEncodeWireValue() {
        #expect(VTGMouseModifiers().wireValue == "none")
        #expect(VTGMouseModifiers([.shift, .control, .alt, .command]).wireValue == "shift|ctrl|alt|cmd")

        let snapshot = VTGMouseSnapshot(
            x: 1,
            y: 2,
            cellX: 3,
            cellY: 4,
            modifiers: [.control, .command]
        )
        #expect(snapshot.modifiers == "ctrl|cmd")
    }

    #if os(macOS)
    @Test func appKitMouseModifiersConvertToVTGModifiers() {
        let flags: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        #expect(flags.vtgMouseModifiers == [.shift, .control, .alt, .command])
        #expect(flags.vtgMouseModifiers.wireValue == "shift|ctrl|alt|cmd")
    }
    #endif

    @Test func ansiMouseModeScannerFindsSequencesInStreamOrder() {
        let bytes = Array("prefix\u{1B}[?1000h middle\u{1B}[?1006h\u{1B}[?1016h later\u{1B}[?1000l\u{1B}[?1016l".utf8)

        #expect(VTGANSIMouseModeScanner.scan(bytes) == [
            .vt200(enabled: true),
            .sgr(enabled: true),
            .pixel(enabled: true),
            .vt200(enabled: false),
            .pixel(enabled: false)
        ])
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
