#if os(macOS)
import AppKit

public extension NSEvent.ModifierFlags {
    /// Convert AppKit-specific modifier flags into SwiftTerm's VTG modifier set.
    var vtgMouseModifiers: VTGMouseModifiers {
        var modifiers: VTGMouseModifiers = []
        if contains(.shift) {
            modifiers.insert(.shift)
        }
        if contains(.control) {
            modifiers.insert(.control)
        }
        if contains(.option) {
            modifiers.insert(.alt)
        }
        if contains(.command) {
            modifiers.insert(.command)
        }
        return modifiers
    }
}
#endif
