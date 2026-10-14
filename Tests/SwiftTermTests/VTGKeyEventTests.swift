import Foundation
import Testing

@testable import SwiftTerm

/// VTG `keyEvents` (VGT-11): a program that asks is told each key going down
/// and coming up, so it can know what is held while several keys are.
@Suite("VTG key events")
struct VTGKeyEventTests {
    private let canvas = VTGCanvasSize(width: 640, height: 480)

    private func command(_ name: String, _ parameters: [String: String] = [:]) -> VectorTerminalGraphicsCommand {
        VectorTerminalGraphicsCommand(name: name, parameters: parameters, payload: nil)
    }

    private func apc(_ body: String) -> String {
        "\u{1B}_VTG;\(body)\u{1B}\\"
    }

    private let left = VTGKeyTransition.Identity(name: "LEFT")

    // MARK: The held-key table

    @Test("A key is down once until it is up; the platform's repeats are repeats")
    func oneDownOneUp() {
        var keys = VTGHeldKeys()
        #expect(keys.press(code: 123, identity: left).kind == .down)
        #expect(keys.press(code: 123, identity: left).kind == .repeat)
        #expect(keys.release(code: 123)?.kind == .up)
        #expect(keys.release(code: 123) == nil, "never reported down, so no up")
    }

    @Test("Holding one key and pressing another leaves the first held")
    func twoKeysHeld() {
        var keys = VTGHeldKeys()
        _ = keys.press(code: 123, identity: left)
        _ = keys.press(code: 49, identity: .init(name: "SPACE"))
        _ = keys.release(code: 49)
        #expect(keys.isHeld(123))
    }

    @Test("Losing focus releases every held key, marked as such")
    func focusLoss() {
        var keys = VTGHeldKeys()
        _ = keys.press(code: 49, identity: .init(name: "SPACE"))
        _ = keys.press(code: 123, identity: left)
        let released = keys.releaseAll()
        #expect(released.map(\.identity.name) == ["SPACE", "LEFT"])
        #expect(released.allSatisfy { $0.kind == .up && $0.lostFocus })
        #expect(keys.isEmpty)
    }

    @Test("Command going down releases the other keys and leaves the modifiers")
    func commandReleasesOthers() {
        var keys = VTGHeldKeys()
        _ = keys.press(code: 56, identity: .init(name: "SHIFT", side: .left))
        _ = keys.press(code: 123, identity: left)
        #expect(keys.releaseAllButModifiers().map(\.identity.name) == ["LEFT"])
        #expect(keys.isHeld(56))
    }

    @Test("The typed character is sent only when it differs from the key's own")
    func typedText() {
        var keys = VTGHeldKeys()
        let one = keys.press(code: 18, identity: .character("1"), text: "!", modifiers: .shift)
        #expect(one.text == "!")
        let a = keys.press(code: 0, identity: .character("a"), text: "a")
        #expect(a.text == nil)
    }

    // MARK: The message

    @Test("The messages")
    func messages() {
        #expect(VTGResponseEncoder.key(.init(kind: .down, identity: left)) == apc("key,type=down,key=LEFT,mods=none"))
        #expect(VTGResponseEncoder.key(.init(kind: .down, identity: .character("1"), text: "!", modifiers: .shift))
            == apc("key,type=down,key=CHAR,char=49,text=33,mods=shift"))
        #expect(VTGResponseEncoder.key(.init(kind: .up, identity: .init(name: "SHIFT", side: .left)))
            == apc("key,type=up,key=SHIFT,side=left,mods=none"))
        #expect(VTGResponseEncoder.key(.init(kind: .up, identity: left, lostFocus: true))
            == apc("key,type=up,key=LEFT,reason=focus,mods=none"))
    }

    // MARK: The host

    private func delivering() -> VTGHostController {
        let controller = VTGHostController()
        controller.deliversKeyEvents = true
        return controller
    }

    @Test("Nothing is sent until the program asks")
    func offByDefault() {
        #expect(delivering().keyResponse(.init(kind: .down, identity: left)) == nil)
    }

    @Test("Subscribed: downs and ups, repeats only when asked for")
    func subscribed() {
        let controller = delivering()
        _ = controller.process([command("keyEvents", ["enabled": "1"])], canvas: canvas)
        #expect(controller.keyResponse(.init(kind: .down, identity: left)) == apc("key,type=down,key=LEFT,mods=none"))
        #expect(controller.keyResponse(.init(kind: .repeat, identity: left)) == nil)
        #expect(controller.keyResponse(.init(kind: .up, identity: left)) != nil)

        _ = controller.process([command("keyEvents", ["enabled": "1", "repeat": "1"])], canvas: canvas)
        #expect(controller.keyResponse(.init(kind: .repeat, identity: left)) == apc("key,type=repeat,key=LEFT,mods=none"))

        _ = controller.process([command("keyEvents", ["enabled": "0"])], canvas: canvas)
        #expect(controller.keyResponse(.init(kind: .down, identity: left)) == nil)
    }

    @Test("Never to a muted host: the terminal's shell is back in front")
    func mutedSendsNothing() {
        let controller = delivering()
        _ = controller.process([command("keyEvents", ["enabled": "1"]), command("mouseEvents", ["enabled": "1", "mode": "all"])], canvas: canvas)
        controller.mute()
        #expect(controller.keyResponse(.init(kind: .down, identity: left)) == nil)
        let snapshot = VTGMouseSnapshot(x: 1, y: 1, cellX: 0, cellY: 0, modifiers: VTGMouseModifiers())
        #expect(controller.mouseResponse(type: .down, button: 0, snapshot: snapshot) == nil, "nor mouse events")
    }

    @Test("A new program starts unsubscribed")
    func resetUnsubscribes() {
        let controller = delivering()
        _ = controller.process([command("keyEvents", ["enabled": "1"])], canvas: canvas)
        controller.resetSession()
        #expect(controller.keyResponse(.init(kind: .down, identity: left)) == nil)
    }

    @Test("Advertised only where keys are delivered")
    func advertisedWhereDelivered() {
        let quiet = VTGHostController()
        let quietCapabilities = quiet.process([command("capabilities?")], canvas: canvas).first ?? ""
        #expect(!quietCapabilities.contains("keyEvents"))
        #expect(!quietCapabilities.contains("|key|") && !quietCapabilities.contains("|key,"))

        let capabilities = delivering().process([command("capabilities?")], canvas: canvas).first ?? ""
        #expect(capabilities.contains("|keyEvents"))
        #expect(capabilities.contains("events=mouse|resize|frame|commandRejected|key,"))
    }

    @Test("Where keys are not delivered the subscription is refused, and says so if asked")
    func refusedWhereNotDelivered() {
        let controller = VTGHostController()
        let responses = controller.process([
            command("errorEvents", ["enabled": "1"]),
            command("keyEvents", ["enabled": "1"]),
        ], canvas: canvas)
        #expect(responses == [apc("commandRejected,command=keyEvents,id=,reason=unsupported")])
        #expect(!controller.sendsKeyEvents)
    }
}

#if os(macOS)
import AppKit

/// The Mac view end to end: a key event in, the `key` message a program reads out.
@MainActor
@Suite("VTG key events from the Mac view")
struct VTGMacKeyEventTests {
    private func keyEvent(_ type: NSEvent.EventType, code: UInt16, characters: String, flags: NSEvent.ModifierFlags = [], isRepeat: Bool = false) -> NSEvent {
        NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: isRepeat, keyCode: code
        )!
    }

    private func subscribedView() -> (VectorTerminalView, () -> [String]) {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var responses: [String] = []
        view.vtgResponseHandler = { responses.append($0) }
        view.feedVTG(Array("\u{1B}_VTG;keyEvents,enabled=1\u{1B}\\".utf8))
        responses.removeAll()
        return (view, { responses })
    }

    @Test("Hold Left, press and let go of Space: Left is still down, and said to be")
    func holdLeftTapSpace() {
        let (view, responses) = subscribedView()
        view.reportKeyDown(keyEvent(.keyDown, code: 123, characters: "\u{F702}"))
        view.reportKeyDown(keyEvent(.keyDown, code: 123, characters: "\u{F702}", isRepeat: true))
        view.reportKeyDown(keyEvent(.keyDown, code: 49, characters: " "))
        view.reportKeyUp(keyEvent(.keyUp, code: 49, characters: " "))
        view.reportKeyUp(keyEvent(.keyUp, code: 123, characters: "\u{F702}"))
        #expect(responses().map { $0.replacingOccurrences(of: "\u{1B}", with: "") } == [
            "_VTG;key,type=down,key=LEFT,mods=none\\",
            "_VTG;key,type=down,key=SPACE,mods=none\\",
            "_VTG;key,type=up,key=SPACE,mods=none\\",
            "_VTG;key,type=up,key=LEFT,mods=none\\",
        ])
    }

    @Test("A Command shortcut is not reported")
    func commandShortcutsAreTheApps() {
        let (view, responses) = subscribedView()
        view.reportKeyDown(keyEvent(.keyDown, code: 13, characters: "w", flags: .command))
        #expect(responses().isEmpty)
    }

    @Test("Modifiers report down and up by side")
    func modifiers() {
        let (view, responses) = subscribedView()
        view.reportModifierChange(keyEvent(.flagsChanged, code: 56, characters: "", flags: NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x2)))
        view.reportModifierChange(keyEvent(.flagsChanged, code: 56, characters: ""))
        #expect(responses().count == 2)
        #expect(responses().first?.contains("type=down,key=SHIFT,side=left") == true)
        #expect(responses().last?.contains("type=up,key=SHIFT,side=left") == true)
    }

    @Test("Losing focus releases what is held")
    func focusLossReleases() {
        let (view, responses) = subscribedView()
        view.reportKeyDown(keyEvent(.keyDown, code: 123, characters: "\u{F702}"))
        view.releaseHeldKeys()
        #expect(responses().last?.contains("type=up,key=LEFT,reason=focus") == true)
    }
}
#endif
