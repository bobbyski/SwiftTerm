import Foundation

/// A physical key going down, repeating, or coming up: what VTG `keyEvents`
/// tells a program that needs to know which keys are held (VGT-11). A terminal
/// otherwise sends only presses and the newest key's repeats, never a release.
public struct VTGKeyTransition: Equatable {
    public enum Kind: String {
        case down, up, `repeat`
    }

    public enum Side: String {
        case left, right
    }

    /// Which key — the same from its down to its up.
    public struct Identity: Equatable {
        /// BASIC's canonical name: `LEFT`, `SPACE`, `SHIFT`, `F5`…, or `CHAR`
        /// for a key that types a character. Never one character long: BASIC
        /// builds that predate key events read a one-character `key=` as
        /// typed input, and would type every letter twice.
        public var name: String
        /// For `CHAR`: the character the key types unshifted.
        public var char: Unicode.Scalar?
        /// For the modifiers: which of the pair.
        public var side: Side?

        public init(name: String, char: Unicode.Scalar? = nil, side: Side? = nil) {
            self.name = name
            self.char = char
            self.side = side
        }

        public static func character(_ scalar: Unicode.Scalar) -> Identity {
            Identity(name: "CHAR", char: scalar)
        }
    }

    public var kind: Kind
    public var identity: Identity
    /// On `down`: the character this press typed, when it is not `char`.
    public var text: Unicode.Scalar?
    public var modifiers: VTGKeyModifiers
    /// A release sent because the terminal lost focus, not because the key
    /// came up while it was looking.
    public var lostFocus: Bool

    public init(
        kind: Kind,
        identity: Identity,
        text: Unicode.Scalar? = nil,
        modifiers: VTGKeyModifiers = [],
        lostFocus: Bool = false
    ) {
        self.kind = kind
        self.identity = identity
        self.text = text
        self.modifiers = modifiers
        self.lostFocus = lostFocus
    }
}

/// The modifiers held with a key, spelled as mouse events spell them.
public struct VTGKeyModifiers: OptionSet, Equatable {
    public let rawValue: Int

    public static let shift = VTGKeyModifiers(rawValue: 1 << 0)
    public static let control = VTGKeyModifiers(rawValue: 1 << 1)
    public static let alt = VTGKeyModifiers(rawValue: 1 << 2)
    public static let command = VTGKeyModifiers(rawValue: 1 << 3)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public var wireValue: String {
        var names: [String] = []
        if contains(.shift) { names.append("shift") }
        if contains(.control) { names.append("ctrl") }
        if contains(.alt) { names.append("alt") }
        if contains(.command) { names.append("cmd") }
        return names.isEmpty ? "none" : names.joined(separator: "|")
    }
}

/// Which keys are down, by the platform's key code, and the transition each
/// press and release makes. One down per key until its up: an auto-repeat of
/// a held key is a `repeat`, never a second `down`.
public struct VTGHeldKeys {
    private var held: [Int: VTGKeyTransition.Identity] = [:]

    public init() {}

    public var isEmpty: Bool { held.isEmpty }

    /// Whether the key with this code is held.
    public func isHeld(_ code: Int) -> Bool {
        held[code] != nil
    }

    /// A press, or the platform's repeat of one.
    public mutating func press(
        code: Int,
        identity: VTGKeyTransition.Identity,
        text: Unicode.Scalar? = nil,
        modifiers: VTGKeyModifiers = []
    ) -> VTGKeyTransition {
        if let existing = held[code] {
            return VTGKeyTransition(kind: .repeat, identity: existing, modifiers: modifiers)
        }
        held[code] = identity
        let typed = text == identity.char ? nil : text
        return VTGKeyTransition(kind: .down, identity: identity, text: typed, modifiers: modifiers)
    }

    /// A release; nil for a key that was never reported down.
    public mutating func release(code: Int, modifiers: VTGKeyModifiers = []) -> VTGKeyTransition? {
        guard let identity = held.removeValue(forKey: code) else { return nil }
        return VTGKeyTransition(kind: .up, identity: identity, modifiers: modifiers)
    }

    /// Releases every held key — the terminal lost focus, and will not see
    /// them come up. In key-code order, so the messages are predictable.
    public mutating func releaseAll() -> [VTGKeyTransition] {
        let released = held.sorted { $0.key < $1.key }.map {
            VTGKeyTransition(kind: .up, identity: $0.value, lostFocus: true)
        }
        held.removeAll()
        return released
    }

    /// Releases the held keys that are not modifiers. AppKit sends no key-up
    /// for a key let go while Command is down, so those are released when
    /// Command goes down rather than left held for ever.
    public mutating func releaseAllButModifiers(modifiers: VTGKeyModifiers = []) -> [VTGKeyTransition] {
        let modifierNames: Set<String> = ["SHIFT", "CONTROL", "OPTION", "COMMAND", "CAPSLOCK"]
        let released = held.filter { !modifierNames.contains($0.value.name) }.sorted { $0.key < $1.key }
        for (code, _) in released {
            held.removeValue(forKey: code)
        }
        return released.map { VTGKeyTransition(kind: .up, identity: $0.value, modifiers: modifiers) }
    }
}

public extension VTGResponseEncoder {
    /// `key,type=…,key=…[,char=…][,text=…][,side=…][,reason=focus],mods=…`
    static func key(_ transition: VTGKeyTransition) -> String {
        var fields: [(String, String)] = [
            ("type", transition.kind.rawValue),
            ("key", transition.identity.name),
        ]
        if let char = transition.identity.char {
            fields.append(("char", String(char.value)))
        }
        if let text = transition.text {
            fields.append(("text", String(text.value)))
        }
        if let side = transition.identity.side {
            fields.append(("side", side.rawValue))
        }
        if transition.lostFocus {
            fields.append(("reason", "focus"))
        }
        fields.append(("mods", transition.modifiers.wireValue))
        return apc("key", fields)
    }
}
