import Testing
@testable import SwiftTerm

/// Stopping the host from talking to a program that has gone.
///
/// A VTG response is only meaningful to the program that asked. When that
/// program exits, anything still on its way is delivered to whatever owns the
/// terminal next — the user's shell — which treats it as typed input:
///
///     ❯ omegaclideVTG;frameStarted,id=tuikit-chrome,timeout=250
///
/// That is what these guard against.
@Suite("VTG response muting")
struct VTGMuteTests {

    private let canvas = VTGCanvasSize(width: 800, height: 600)

    /// Builds a VTG command from its wire text, e.g. `VTG;startFrame,id=x`.
    ///
    /// The leading `V` travels as the sequence's command byte and the rest as
    /// its data, which is how the parser receives one off the wire.
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

    @Test("A frame is acknowledged while a program is listening")
    func framesAnswerNormally() {
        let controller = VTGHostController()
        let started = process(controller, "VTG;startFrame,id=chrome")
        #expect(started.contains { $0.contains("frameStarted") },
                "the acknowledgement is what a program waits on")
    }

    @Test("Detach silences the acknowledgements")
    func detachStopsResponses() {
        let controller = VTGHostController()
        _ = process(controller, "VTG;detach")
        #expect(controller.isMuted)

        let started = process(controller, "VTG;startFrame,id=chrome")
        #expect(started.isEmpty, "this is the reply that ends up typed into the shell")
        let ended = process(controller, "VTG;endFrame,id=chrome")
        #expect(ended.isEmpty)
    }

    @Test("Detach itself says nothing back")
    func detachIsSilent() {
        let controller = VTGHostController()
        #expect(process(controller, "VTG;detach").isEmpty,
                "a goodbye that replies is the very thing being prevented")
    }

    @Test("A frame left open is abandoned, not acknowledged later")
    func detachDropsAnOpenFrame() {
        let controller = VTGHostController()
        _ = process(controller, "VTG;startFrame,id=chrome")
        #expect(controller.hasPendingFrame)

        _ = process(controller, "VTG;detach")
        #expect(controller.hasPendingFrame == false,
                "its commit or timeout would be a reply with nobody to receive it")
    }

    @Test("Commands still take effect while muted")
    func mutedStillApplies() {
        let controller = VTGHostController()
        _ = process(controller, "VTG;rect,id=box,x=0,y=0,width=10,height=10,fill=#ffffff")
        #expect(controller.scene.primitives.isEmpty == false)

        _ = process(controller, "VTG;detach")
        // A program on its way out clears its graphics; that has to land, or
        // its drawing outlives it on the user's screen.
        _ = process(controller, "VTG;clear")
        #expect(controller.scene.primitives.isEmpty,
                "muting stops the talking back, not the doing")
    }

    @Test("A new program gets a talking host again")
    func unmuteRestoresResponses() {
        let controller = VTGHostController()
        _ = process(controller, "VTG;detach")
        controller.unmute()

        let started = process(controller, "VTG;startFrame,id=next")
        #expect(started.contains { $0.contains("frameStarted") },
                "the next program has its own conversation")
    }

    @Test("A probe is answered even after the host guessed the program had gone")
    func guessDoesNotSilenceTheNextProgram() {
        let controller = VTGHostController()
        // What the host does between programs: it saw the shell in the
        // foreground and assumed nothing was listening.
        controller.mute()

        // `swift run` builds with the shell in the foreground, so the guess
        // lands moments before the program it is about to start probes.
        let answer = process(controller, "VTG;capabilities?")
        #expect(answer.isEmpty == false,
                "a program told there are no graphics draws plain cells instead")
        #expect(controller.isMuted == false, "the command proved the guess wrong")
    }

    @Test("A goodbye is final, and a stray command does not undo it")
    func detachOutranksALaterCommand() {
        let controller = VTGHostController()
        _ = process(controller, "VTG;detach")

        // Anything still in the pipe when the program said it was done.
        #expect(process(controller, "VTG;capabilities?").isEmpty,
                "the program said it was finished; that is not a guess to revisit")
        #expect(controller.isMuted)
    }

    @Test("A guess never downgrades a goodbye")
    func muteDoesNotWeakenDetach() {
        let controller = VTGHostController()
        _ = process(controller, "VTG;detach")
        controller.mute()
        #expect(process(controller, "VTG;capabilities?").isEmpty)
    }

    @Test("Muting is what the host does when a program is killed")
    func muteCoversTheSignalCase() {
        // Ctrl-C leaves no chance to send `detach`, so the embedding view mutes
        // on the program's behalf once it notices it is gone.
        let controller = VTGHostController()
        _ = process(controller, "VTG;startFrame,id=chrome")
        controller.mute()

        #expect(controller.hasPendingFrame == false)
        #expect(process(controller, "VTG;endFrame,id=chrome").isEmpty)
    }
}
