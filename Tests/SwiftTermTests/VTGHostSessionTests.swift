import Foundation
import Testing

@testable import SwiftTerm

final class VTGHostSessionTests {
    @Test func privateSequenceSendsResponsesAndPublishesSceneChanges() {
        var canvas = VTGCanvasSize(width: 320, height: 200)
        var processRunning = true
        var responses: [String] = []
        var sceneChangeCount = 0

        let session = VTGHostSession(
            canvasProvider: { canvas },
            processRunning: { processRunning },
            sendResponse: { responses.append($0) },
            sceneDidChange: { scene in
                sceneChangeCount += 1
                #expect(scene.primitives.count == 1)
            }
        )

        let sequence = TerminalPrivateSequence(
            kind: .apc,
            command: Int(UInt8(ascii: "V")),
            data: Array("TG;line,id=a,x1=1,y1=2,x2=3,y2=4".utf8)[...]
        )

        #expect(session.handlePrivateSequence(sequence))
        #expect(responses.isEmpty)
        #expect(sceneChangeCount == 1)

        let resizeSubscription = TerminalPrivateSequence(
            kind: .apc,
            command: Int(UInt8(ascii: "V")),
            data: Array("TG;resizeEvents,enabled=1".utf8)[...]
        )

        #expect(session.handlePrivateSequence(resizeSubscription))
        #expect(responses.last?.contains("_VTG;resize,width=320,height=200") == true)

        responses.removeAll()
        session.notifyResizeIfNeeded()
        #expect(responses.isEmpty)

        canvas = VTGCanvasSize(width: 360, height: 200)
        session.notifyResizeIfNeeded()
        #expect(responses.last?.contains("_VTG;resize,width=360,height=200") == true)

        responses.removeAll()
        processRunning = false
        canvas = VTGCanvasSize(width: 400, height: 200)
        session.notifyResizeIfNeeded(force: true)
        #expect(responses.isEmpty)
    }

    @Test func mouseEventSendsOnlyWhenSubscribedAndAccepted() {
        var responses: [String] = []
        let session = VTGHostSession(
            canvasProvider: { VTGCanvasSize(width: 100, height: 100) },
            processRunning: { true },
            sendResponse: { responses.append($0) },
            sceneDidChange: { _ in }
        )
        let snapshot = VTGMouseSnapshot(x: 10, y: 20, cellX: 1, cellY: 2, modifiers: "none")

        #expect(!session.sendMouseEvent(type: .click, button: 0, snapshot: snapshot))

        let subscription = TerminalPrivateSequence(
            kind: .apc,
            command: Int(UInt8(ascii: "V")),
            data: Array("TG;mouseEvents,enabled=1,mode=click".utf8)[...]
        )
        #expect(session.handlePrivateSequence(subscription))

        #expect(!session.sendMouseEvent(type: .down, button: 0, snapshot: snapshot))
        #expect(session.sendMouseEvent(type: .click, button: 0, snapshot: snapshot))
        #expect(responses.last?.contains("_VTG;mouse,type=click") == true)
    }

    @Test func discardPendingFramePublishesVisibleScene() {
        var publishedPrimitiveIDs: [[String]] = []
        let session = VTGHostSession(
            canvasProvider: { VTGCanvasSize(width: 100, height: 100) },
            processRunning: { true },
            sendResponse: { _ in },
            sceneDidChange: { scene in
                publishedPrimitiveIDs.append(scene.primitives.map(\.id))
            }
        )

        _ = session.controller.process([
            VectorTerminalGraphicsCommand(
                name: "line",
                parameters: ["id": "visible", "x1": "0", "y1": "0", "x2": "10", "y2": "10"]
            ),
            VectorTerminalGraphicsCommand(name: "startFrame", parameters: ["id": "frame1"]),
            VectorTerminalGraphicsCommand(
                name: "rect",
                parameters: ["id": "pending", "x": "1", "y": "2", "w": "30", "h": "40"]
            )
        ], canvas: VTGCanvasSize(width: 100, height: 100))

        session.discardPendingFrame()

        #expect(publishedPrimitiveIDs.last == ["visible"])
        #expect(!session.controller.hasPendingFrame)
    }

    @Test func visibleSceneAccessorsExposeOnlyCommittedCompositingPlanes() {
        let session = VTGHostSession(
            canvasProvider: { VTGCanvasSize(width: 100, height: 100) },
            processRunning: { true },
            sendResponse: { _ in },
            sceneDidChange: { _ in }
        )

        _ = session.controller.process([
            VectorTerminalGraphicsCommand(
                name: "line",
                parameters: [
                    "id": "textPlane",
                    "layer": "0",
                    "x1": "0",
                    "y1": "0",
                    "x2": "10",
                    "y2": "10"
                ]
            ),
            VectorTerminalGraphicsCommand(
                name: "rect",
                parameters: [
                    "id": "underText",
                    "layer": "-1",
                    "x": "0",
                    "y": "0",
                    "w": "20",
                    "h": "20"
                ]
            ),
            VectorTerminalGraphicsCommand(
                name: "rect",
                parameters: [
                    "id": "overlay",
                    "layer": "1",
                    "x": "1",
                    "y": "2",
                    "w": "30",
                    "h": "40"
                ]
            ),
            VectorTerminalGraphicsCommand(name: "startFrame", parameters: ["id": "frame1"]),
            VectorTerminalGraphicsCommand(
                name: "circle",
                parameters: [
                    "id": "pending",
                    "layer": "0",
                    "cx": "5",
                    "cy": "5",
                    "r": "2"
                ]
            )
        ], canvas: VTGCanvasSize(width: 100, height: 100))

        #expect(session.visibleSceneSnapshot.primitives.map(\.id) == ["textPlane", "underText", "overlay"])
        #expect(session.visiblePrimitives(in: .underText).map(\.id) == ["underText"])
        #expect(session.visiblePrimitives(in: .textPlane).map(\.id) == ["textPlane"])
        #expect(session.visiblePrimitives(in: .overlay).map(\.id) == ["overlay"])
    }
}
