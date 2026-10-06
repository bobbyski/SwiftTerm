import Testing
@testable import SwiftTerm

/// A program hiding and showing the graphics layers (`graphicsVisible`).
///
/// The user has a say too, through the host's Show Graphics menu. The two
/// must not fight: a program's choice lasts while it runs, the user's toggle
/// wins, and a program that leaves never leaves the graphics hidden (VGT-2).
@Suite("VTG graphics visibility")
struct VTGGraphicsVisibilityTests {

    private let canvas = VTGCanvasSize(width: 800, height: 600)

    /// Builds a VTG command from its wire text, e.g. `VTG;graphicsVisible,enabled=0`.
    private func command(_ text: String) -> VectorTerminalGraphicsCommand? {
        precondition(text.hasPrefix("V"))
        return VectorTerminalGraphicsParser().command(
            from: TerminalPrivateSequence(
                kind: .apc,
                command: Int(UInt8(ascii: "V")),
                data: Array(text.dropFirst().utf8)[...]
            ))
    }

    private func process(_ controller: VTGHostController, _ text: String) -> [String] {
        guard let command = command(text) else { return [] }
        return controller.process([command], canvas: canvas)
    }

    /// A controller with a program's `graphicsVisible` changes recorded.
    private func observed() -> (VTGHostController, Changes) {
        let controller = VTGHostController()
        let changes = Changes()
        controller.graphicsLayersVisibleDidChange = { changes.values.append($0) }
        return (controller, changes)
    }

    private final class Changes {
        var values: [Bool] = []
    }

    @Test("A program hides and shows the graphics, and the host is told")
    func programHidesAndShows() {
        let (controller, changes) = observed()
        _ = process(controller, "VTG;rect,id=box,x=0,y=0,width=10,height=10,fill=#ffffff")
        _ = process(controller, "VTG;graphicsVisible,enabled=0")
        #expect(controller.graphicsLayersVisible == false)
        #expect(controller.scene.primitives.isEmpty == false, "hidden, not cleared")
        #expect(process(controller, "VTG;graphicsVisible?").first?.contains("visible=0") == true)

        _ = process(controller, "VTG;graphicsVisible,enabled=1")
        #expect(controller.graphicsLayersVisible)
        #expect(changes.values == [false, true])
    }

    @Test("The program's choice is not taken for the user's")
    func userChoiceKept() {
        let (controller, _) = observed()
        _ = process(controller, "VTG;graphicsVisible,enabled=0")
        #expect(controller.hostGraphicsLayersVisible == true, "the user had them showing")
        _ = process(controller, "VTG;graphicsVisible,enabled=1")
        _ = process(controller, "VTG;graphicsVisible,enabled=0")
        #expect(controller.hostGraphicsLayersVisible == true, "still the user's, not the program's first change")
    }

    @Test("A program that detaches leaves the graphics as the user had them")
    func detachRestores() {
        let (controller, changes) = observed()
        _ = process(controller, "VTG;graphicsVisible,enabled=0")
        _ = process(controller, "VTG;detach")
        #expect(controller.graphicsLayersVisible)
        #expect(controller.hostGraphicsLayersVisible == nil)
        #expect(changes.values == [false, true])
    }

    @Test("A program that has gone, or a reset, leaves them as the user had them")
    func muteAndResetRestore() {
        let (gone, _) = observed()
        _ = process(gone, "VTG;graphicsVisible,enabled=0")
        gone.mute()
        #expect(gone.graphicsLayersVisible)

        let (reset, _) = observed()
        _ = process(reset, "VTG;graphicsVisible,enabled=0")
        reset.resetSession()
        #expect(reset.graphicsLayersVisible)
    }

    @Test("Graphics the user hid stay hidden when a program that showed them leaves")
    func userHiddenStaysHidden() {
        let (controller, changes) = observed()
        controller.setGraphicsLayersVisible(false)
        _ = process(controller, "VTG;graphicsVisible,enabled=1")
        #expect(controller.graphicsLayersVisible)
        controller.mute()
        #expect(controller.graphicsLayersVisible == false)
        #expect(changes.values == [true, false])
    }

    @Test("The user's toggle wins, and is what a departing program leaves")
    func userToggleWins() {
        let (controller, changes) = observed()
        _ = process(controller, "VTG;graphicsVisible,enabled=0")
        controller.setGraphicsLayersVisible(true)
        #expect(controller.hostGraphicsLayersVisible == nil)
        controller.setGraphicsLayersVisible(false)
        _ = process(controller, "VTG;detach")
        #expect(controller.graphicsLayersVisible == false, "the user hid them last")
        #expect(changes.values == [false], "the host's own changes are not reported back to it")
    }

    @Test("Nothing is reported when nothing changes")
    func quietWhenUnchanged() {
        let (controller, changes) = observed()
        _ = process(controller, "VTG;graphicsVisible,enabled=1")
        controller.mute()
        #expect(changes.values.isEmpty)
    }

    @Test("The session tells its host and redraws when the host's choice comes back")
    func sessionRestore() {
        var scenes = 0
        var told: [Bool] = []
        let session = VTGHostSession(
            canvasProvider: { VTGCanvasSize(width: 800, height: 600) },
            processRunning: { true },
            sendResponse: { _ in },
            sceneDidChange: { _ in scenes += 1 }
        )
        session.graphicsLayersVisibleDidChange = { told.append($0) }
        guard let hide = command("VTG;graphicsVisible,enabled=0") else {
            Issue.record("the command did not parse")
            return
        }
        _ = session.controller.process([hide], canvas: canvas)
        let before = scenes
        session.restoreHostGraphicsLayersVisible()
        #expect(session.graphicsLayersVisible)
        #expect(scenes == before + 1, "the overlay is shown again")
        #expect(told == [false, true])

        session.restoreHostGraphicsLayersVisible()
        #expect(scenes == before + 1, "nothing to put back, nothing redrawn")
    }
}

#if os(macOS)
import AppKit

/// The same, end to end on a real terminal view: bytes in through the
/// terminal parser, the overlay shown or hidden, and the host told.
@MainActor
@Suite("VTG graphics visibility on a terminal view")
struct VTGGraphicsVisibilityViewTests {
    private let esc = "\u{1B}"

    private func feed(_ view: VectorTerminalView, _ commands: String...) {
        for command in commands {
            view.feedVTG(Data("\(esc)_VTG;\(command)\(esc)\\".utf8))
        }
    }

    @Test("A program's hide reaches the overlay and the host, and a prompt mark undoes it")
    func promptMarkRestores() {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var told: [Bool] = []
        view.onGraphicsLayersVisibleChange = { told.append($0) }

        feed(view, "rect,id=box,x=0,y=0,w=10,h=10,fill=#ff0000", "graphicsVisible,enabled=0")
        #expect(!view.areGraphicsLayersVisible)
        #expect(view.vtgOverlayView.isHidden)

        view.feed(text: "\(esc)]133;C\u{7}")
        #expect(!view.areGraphicsLayersVisible, "output-start is not a prompt")
        view.feed(text: "\(esc)]133;D;0\u{7}")
        #expect(view.areGraphicsLayersVisible, "command-end means the program has gone")
        #expect(!view.vtgOverlayView.isHidden)
        #expect(told == [false, true])
    }

    @Test("A terminal reset undoes a program's hide, but not the user's")
    func resetRestores() {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        feed(view, "graphicsVisible,enabled=0")
        view.feed(text: "\(esc)c")
        #expect(view.areGraphicsLayersVisible)

        view.setGraphicsLayersVisible(false)
        view.feed(text: "\(esc)c")
        #expect(!view.areGraphicsLayersVisible, "the user hid them")
    }
}
#endif
