//
//  iOSTerminalView+KeyTransitions.swift
//
//  Hardware keys going down and coming up, for `keyTransitionObserver`: what
//  VTG `keyEvents` reports to a program that needs to know which keys are
//  held (VGT-11). The on-screen keyboard has no key identity and reports
//  nothing. The keys' bytes are sent exactly as before; this only tells.
//
#if os(iOS) || os(visionOS)
import UIKit

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
    /// Presses went down. Called before the view or the text system acts on
    /// them, so a key's `down` reaches the program ahead of what it types.
    func reportPressesBegan(_ presses: Set<UIPress>) {
        guard let keyTransitionObserver else { return }
        for press in presses {
            guard let key = press.key, let identity = Self.keyIdentity(for: key) else { continue }
            let modifiers = VTGKeyModifiers(key.modifierFlags)
            if identity.name == "COMMAND" {
                // As on the Mac: a Command shortcut's keys are the app's.
                heldKeys.releaseAllButModifiers(modifiers: modifiers).forEach(keyTransitionObserver)
            } else if key.modifierFlags.contains(.command), !Self.isModifier(identity) {
                continue
            }
            keyTransitionObserver(heldKeys.press(
                code: Int(key.keyCode.rawValue),
                identity: identity,
                text: Self.typedScalar(of: key),
                modifiers: modifiers
            ))
        }
    }

    /// Presses came up, or the system took them away.
    func reportPressesEnded(_ presses: Set<UIPress>) {
        guard let keyTransitionObserver else { return }
        for press in presses {
            guard let key = press.key,
                  let up = heldKeys.release(code: Int(key.keyCode.rawValue), modifiers: VTGKeyModifiers(key.modifierFlags))
            else { continue }
            keyTransitionObserver(up)
        }
    }

    /// The view stopped seeing keys — it lost first responder or the app is
    /// going to the background — so every held key is released.
    func releaseHeldKeys() {
        let released = heldKeys.releaseAll()
        guard let keyTransitionObserver else { return }
        released.forEach(keyTransitionObserver)
    }

    func watchFocusForHeldKeys() {
        keyFocusWatch.removeAll()
        guard keyTransitionObserver != nil else { return }
        keyFocusWatch.tokens = [
            NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.releaseHeldKeys()
            },
        ]
    }

    /// Stops the repeat timer when the key it repeats is among `presses`.
    /// Only that key's release stops it: letting go of Space must not stop a
    /// held arrow, which it used to.
    func stopKeyRepeat(releasing presses: Set<UIPress>) {
        guard let code = keyRepeatCode, presses.contains(where: { $0.key?.keyCode == code }) else { return }
        keyRepeat?.invalidate()
        keyRepeat = nil
        keyRepeatCode = nil
    }

    /// BASIC's name for `key`, by its position on the keyboard; `CHAR` and the
    /// unshifted character for one that types.
    static func keyIdentity(for key: UIKey) -> VTGKeyTransition.Identity? {
        let usage = key.keyCode
        if let name = namedKeys[usage] {
            return .init(name: name)
        }
        if let modifier = modifierKeys[usage] {
            return modifier
        }
        let f1 = UIKeyboardHIDUsage.keyboardF1.rawValue, f12 = UIKeyboardHIDUsage.keyboardF12.rawValue
        let f13 = UIKeyboardHIDUsage.keyboardF13.rawValue, f24 = UIKeyboardHIDUsage.keyboardF24.rawValue
        if (f1...f12).contains(usage.rawValue) {
            return .init(name: "F\(usage.rawValue - f1 + 1)")
        }
        if (f13...f24).contains(usage.rawValue) {
            return .init(name: "F\(usage.rawValue - f13 + 13)")
        }
        guard var scalar = key.charactersIgnoringModifiers.unicodeScalars.first, isTyped(scalar) else {
            return nil
        }
        // Unshifted, as the Mac reports it.
        if (65...90).contains(scalar.value), let lower = Unicode.Scalar(scalar.value + 32) {
            scalar = lower
        }
        return .character(scalar)
    }

    static func typedScalar(of key: UIKey) -> Unicode.Scalar? {
        guard let scalar = key.characters.unicodeScalars.first, isTyped(scalar) else { return nil }
        return scalar
    }

    private static func isTyped(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value > 32 && scalar.value != 127
    }

    private static func isModifier(_ identity: VTGKeyTransition.Identity) -> Bool {
        ["SHIFT", "CONTROL", "OPTION", "COMMAND", "CAPSLOCK"].contains(identity.name)
    }

    private static let namedKeys: [UIKeyboardHIDUsage: String] = [
        .keyboardLeftArrow: "LEFT", .keyboardRightArrow: "RIGHT",
        .keyboardUpArrow: "UP", .keyboardDownArrow: "DOWN",
        .keyboardHome: "HOME", .keyboardEnd: "END",
        .keyboardPageUp: "PAGEUP", .keyboardPageDown: "PAGEDOWN",
        .keyboardInsert: "INSERT", .keyboardDeleteForward: "DELETE",
        .keyboardReturnOrEnter: "ENTER", .keyboardReturn: "ENTER", .keypadEnter: "ENTER",
        .keyboardTab: "TAB", .keyboardEscape: "ESCAPE",
        .keyboardDeleteOrBackspace: "BACKSPACE", .keyboardSpacebar: "SPACE",
        .keyboardCapsLock: "CAPSLOCK",
    ]

    private static let modifierKeys: [UIKeyboardHIDUsage: VTGKeyTransition.Identity] = [
        .keyboardLeftShift: .init(name: "SHIFT", side: .left),
        .keyboardRightShift: .init(name: "SHIFT", side: .right),
        .keyboardLeftControl: .init(name: "CONTROL", side: .left),
        .keyboardRightControl: .init(name: "CONTROL", side: .right),
        .keyboardLeftAlt: .init(name: "OPTION", side: .left),
        .keyboardRightAlt: .init(name: "OPTION", side: .right),
        .keyboardLeftGUI: .init(name: "COMMAND", side: .left),
        .keyboardRightGUI: .init(name: "COMMAND", side: .right),
    ]
}

extension VTGKeyModifiers {
    init(_ flags: UIKeyModifierFlags) {
        self = []
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.alternate) { insert(.alt) }
        if flags.contains(.command) { insert(.command) }
    }
}
#endif
