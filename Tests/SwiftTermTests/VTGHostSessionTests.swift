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
}
