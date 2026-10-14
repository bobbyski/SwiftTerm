//
//  MacTerminalView+KeyTransitions.swift
//
//  Physical keys going down and coming up, for `keyTransitionObserver`: what
//  VTG `keyEvents` reports to a program that needs to know which keys are
//  held (VGT-11). The keys' bytes are sent exactly as before; this only tells.
//
#if os(macOS)
import AppKit

/// Removes notification observers when the view goes.
final class KeyFocusWatch {
    var tokens: [NSObjectProtocol] = []

    func removeAll() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
    }

    deinit {
        removeAll()
    }
}

extension TerminalView {
    /// A key went down, or AppKit repeated it. Called before the view acts on
    /// it, so a key's `down` reaches the program ahead of the bytes it types.
    func reportKeyDown(_ event: NSEvent) {
        guard let keyTransitionObserver else { return }
        // A Command shortcut belongs to the app, and AppKit sends it no key-up.
        guard !event.modifierFlags.contains(.command),
              let identity = Self.keyIdentity(for: event) else {
            return
        }
        keyTransitionObserver(heldKeys.press(
            code: Int(event.keyCode),
            identity: identity,
            text: Self.typedScalar(of: event),
            modifiers: VTGKeyModifiers(event.modifierFlags)
        ))
    }

    func reportKeyUp(_ event: NSEvent) {
        guard let keyTransitionObserver,
              let transition = heldKeys.release(code: Int(event.keyCode), modifiers: VTGKeyModifiers(event.modifierFlags))
        else { return }
        keyTransitionObserver(transition)
    }

    /// A modifier key went down or came up. Read from the device-specific
    /// flag bits rather than toggled, so a modifier pressed while the view was
    /// not looking cannot leave the table upside down.
    func reportModifierChange(_ event: NSEvent) {
        guard let keyTransitionObserver else { return }
        let code = Int(event.keyCode)
        let modifiers = VTGKeyModifiers(event.modifierFlags)
        if code == 57 {
            // Caps Lock: macOS reports each press and never the release.
            keyTransitionObserver(heldKeys.press(code: code, identity: .init(name: "CAPSLOCK"), modifiers: modifiers))
            if let up = heldKeys.release(code: code, modifiers: modifiers) {
                keyTransitionObserver(up)
            }
            return
        }
        guard let (identity, mask) = Self.modifierKey(code: code) else { return }
        if event.modifierFlags.rawValue & mask != 0 {
            guard !heldKeys.isHeld(code) else { return }
            if identity.name == "COMMAND" {
                // Keys let go while Command is down send no key-up.
                heldKeys.releaseAllButModifiers(modifiers: modifiers).forEach(keyTransitionObserver)
            }
            keyTransitionObserver(heldKeys.press(code: code, identity: identity, modifiers: modifiers))
        } else if let up = heldKeys.release(code: code, modifiers: modifiers) {
            keyTransitionObserver(up)
        }
    }

    /// The view stopped seeing keys — it lost first responder, its window
    /// stopped being key, or the app went to the background — so every held
    /// key is released: the view will not see them come up.
    func releaseHeldKeys() {
        let released = heldKeys.releaseAll()
        guard let keyTransitionObserver else { return }
        released.forEach(keyTransitionObserver)
    }

    func watchFocusForHeldKeys() {
        keyFocusWatch.removeAll()
        guard keyTransitionObserver != nil else { return }
        let center = NotificationCenter.default
        keyFocusWatch.tokens = [
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let window = note.object as? NSWindow, window === self.window else { return }
                self.releaseHeldKeys()
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.releaseHeldKeys()
            },
        ]
    }

    /// BASIC's name for the key `event` is about, by its position on the
    /// keyboard; `CHAR` and the unshifted character for one that types.
    static func keyIdentity(for event: NSEvent) -> VTGKeyTransition.Identity? {
        if let name = namedKeys[Int(event.keyCode)] {
            return .init(name: name)
        }
        guard let scalar = event.characters(byApplyingModifiers: [])?.unicodeScalars.first,
              isTyped(scalar) else {
            return nil
        }
        return .character(scalar)
    }

    /// The character this press typed, with its modifiers.
    static func typedScalar(of event: NSEvent) -> Unicode.Scalar? {
        guard let scalar = event.characters?.unicodeScalars.first, isTyped(scalar) else { return nil }
        return scalar
    }

    /// A printable character: not a control, not space (which has a name),
    /// and not AppKit's private-use scalars for function keys.
    private static func isTyped(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value > 32 && scalar.value != 127 && !(0xF700...0xF8FF).contains(scalar.value)
    }

    /// Keys with names, by AppKit key code.
    private static let namedKeys: [Int: String] = [
        123: "LEFT", 124: "RIGHT", 125: "DOWN", 126: "UP",
        115: "HOME", 119: "END", 116: "PAGEUP", 121: "PAGEDOWN",
        114: "INSERT", 117: "DELETE",
        36: "ENTER", 76: "ENTER", 48: "TAB", 53: "ESCAPE", 51: "BACKSPACE", 49: "SPACE",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    /// The modifier keys, by key code, with the device-specific flag bit that
    /// says whether that one key is down.
    private static func modifierKey(code: Int) -> (VTGKeyTransition.Identity, UInt)? {
        switch code {
        case 56: return (.init(name: "SHIFT", side: .left), 0x0002)
        case 60: return (.init(name: "SHIFT", side: .right), 0x0004)
        case 59: return (.init(name: "CONTROL", side: .left), 0x0001)
        case 62: return (.init(name: "CONTROL", side: .right), 0x2000)
        case 58: return (.init(name: "OPTION", side: .left), 0x0020)
        case 61: return (.init(name: "OPTION", side: .right), 0x0040)
        case 55: return (.init(name: "COMMAND", side: .left), 0x0008)
        case 54: return (.init(name: "COMMAND", side: .right), 0x0010)
        default: return nil
        }
    }
}

extension VTGKeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.alt) }
        if flags.contains(.command) { insert(.command) }
    }
}
#endif
