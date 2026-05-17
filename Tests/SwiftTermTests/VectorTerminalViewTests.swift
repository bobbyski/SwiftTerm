#if os(macOS)
import AppKit
import Testing

@testable import SwiftTerm

@MainActor
final class VectorTerminalViewTests {
    private let esc = "\u{1B}"

    @Test func vectorTerminalViewInstallsOverlayWithoutChangingPlainTerminalView() {
        let plain = TerminalView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        let vector = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))

        #expect(!plain.subviews.contains { $0 is VTGOverlayView })
        #expect(vector.vtgOverlayView.superview === vector)
    }

    @Test func hostFedVTGSequencesUpdateOverlaySceneAndResponses() {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        var responses: [String] = []
        view.vtgResponseHandler = { responses.append($0) }

        view.feedVTG(Data("\(esc)_VTG;capabilities?\(esc)\\".utf8))
        view.feedVTG(Data("\(esc)_VTG;rect,id=test,x=10,y=20,w=30,h=40,stroke=#22c55e,fill=none,width=1\(esc)\\".utf8))

        #expect(responses.contains { $0.contains("_VTG;capabilities") })
        #expect(view.vtgOverlayView.scene?.renderPrimitives.count == 1)
    }

    @Test func hostFedDeactivationDiscardsPendingOffscreenFrame() {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))

        view.feedVTG(Data("\(esc)_VTG;line,id=visible,x1=10,y1=10,x2=100,y2=10,stroke=#22c55e,width=2\(esc)\\".utf8))
        view.feedVTG(Data("\(esc)_VTG;startFrame,id=test\(esc)\\".utf8))
        view.feedVTG(Data("\(esc)_VTG;clear\(esc)\\".utf8))
        view.feedVTG(Data("\(esc)_VTG;rect,id=pending,x=10,y=20,w=30,h=40,stroke=#22c55e,fill=none,width=1\(esc)\\".utf8))

        #expect(view.vtgSession.controller.hasPendingFrame)

        view.setVTGHostActive(false)

        #expect(!view.vtgSession.controller.hasPendingFrame)
        #expect(view.vtgOverlayView.scene?.renderPrimitives.map(\.id) == ["visible"])
    }

    @Test func localProcessTerminationDiscardsPendingOffscreenFrame() {
        let view = LocalProcessVectorTerminalView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))

        view.feedVTG(Data("\(esc)_VTG;line,id=visible,x1=10,y1=10,x2=100,y2=10,stroke=#22c55e,width=2\(esc)\\".utf8))
        view.feedVTG(Data("\(esc)_VTG;startFrame,id=test\(esc)\\".utf8))
        view.feedVTG(Data("\(esc)_VTG;clear\(esc)\\".utf8))
        view.feedVTG(Data("\(esc)_VTG;rect,id=pending,x=10,y=20,w=30,h=40,stroke=#22c55e,fill=none,width=1\(esc)\\".utf8))

        #expect(view.vtgSession.controller.hasPendingFrame)

        view.processTerminated(view.process, exitCode: nil)

        #expect(!view.vtgSession.controller.hasPendingFrame)
        #expect(view.vtgOverlayView.scene?.renderPrimitives.map(\.id) == ["visible"])
    }
}
#endif
