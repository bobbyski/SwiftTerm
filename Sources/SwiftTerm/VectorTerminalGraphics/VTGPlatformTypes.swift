#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreGraphics

// One VTG view layer for both frameworks, not an AppKit copy and a UIKit copy.
//
// The drawing files are arithmetic and CGContext calls that do not care which
// framework drew the rectangle, so they name these aliases and compile twice.
// Only what genuinely differs — the current context, marking a view dirty, a
// color's initializer — is written per platform, and it is written here.
//
// What deliberately stays macOS-only: LocalProcess* (a pty is what iOS does
// not have) and VTGMouse+AppKit (touch is its own design, not an alias).

#if os(macOS)

/// The framework's view class: `NSView` on macOS, `UIView` on iOS.
public typealias VTGPlatformView = NSView
/// The framework's color class, used where a `CGColor` will not do.
public typealias VTGPlatformColor = NSColor
/// The framework's image class, used to draw sprite assets.
public typealias VTGPlatformImage = NSImage
/// The framework's font class, used for immediate-mode text.
public typealias VTGPlatformFont = NSFont

#else

public typealias VTGPlatformView = UIView
public typealias VTGPlatformColor = UIColor
public typealias VTGPlatformImage = UIImage
public typealias VTGPlatformFont = UIFont

#endif

/// The Core Graphics context the current `draw(_:)` is drawing into.
///
/// AppKit hands it over through the current `NSGraphicsContext`; UIKit pushes
/// it onto its own stack. Both are valid only inside a draw call.
func vtgCurrentCGContext() -> CGContext? {
    #if os(macOS)
    return NSGraphicsContext.current?.cgContext
    #else
    return UIGraphicsGetCurrentContext()
    #endif
}

/// Make `context` the framework's current drawing context.
///
/// Text and images drawn through `String.draw(at:)` or an image's `draw(in:)`
/// go to the framework's current context, not to a `CGContext` passed around
/// in Swift — so rendering into an off-screen layer has to install it. The
/// caller must balance this with `vtgPopDrawingContext()`.
///
/// The context is expected to be flipped already (top-left origin), which is
/// how the rest of VTG draws.
func vtgPushDrawingContext(_ context: CGContext) {
    #if os(macOS)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    #else
    UIGraphicsPushContext(context)
    #endif
}

/// Restore whatever was current before `vtgPushDrawingContext(_:)`.
func vtgPopDrawingContext() {
    #if os(macOS)
    NSGraphicsContext.restoreGraphicsState()
    #else
    UIGraphicsPopContext()
    #endif
}

extension VTGPlatformView {
    /// Add `view` on top of `sibling`, or on top of everything when nil.
    ///
    /// AppKit orders with `addSubview(_:positioned:relativeTo:)`; UIKit has
    /// `insertSubview(_:aboveSubview:)` and appends to the top by default.
    func vtgAddSubview(_ view: VTGPlatformView, above sibling: VTGPlatformView?) {
        #if os(macOS)
        addSubview(view, positioned: .above, relativeTo: sibling)
        #else
        if let sibling {
            insertSubview(view, aboveSubview: sibling)
        } else {
            addSubview(view)
        }
        #endif
    }

    /// Add `view` underneath `sibling`.
    func vtgAddSubview(_ view: VTGPlatformView, below sibling: VTGPlatformView) {
        #if os(macOS)
        addSubview(view, positioned: .below, relativeTo: sibling)
        #else
        insertSubview(view, belowSubview: sibling)
        #endif
    }

    /// Mark the whole view as needing to be redrawn.
    ///
    /// `needsDisplay = true` is AppKit's spelling and `setNeedsDisplay()` is
    /// UIKit's; `NSView` has no zero-argument `setNeedsDisplay()`.
    func vtgSetNeedsDisplay() {
        #if os(macOS)
        needsDisplay = true
        #else
        setNeedsDisplay()
        #endif
    }

    /// Lay this view and its subviews out now, so bounds can be measured.
    func vtgLayoutIfNeeded() {
        #if os(macOS)
        layoutSubtreeIfNeeded()
        #else
        layoutIfNeeded()
        #endif
    }

    /// Make the view layer-backed and genuinely transparent.
    ///
    /// `wantsLayer` is an AppKit-only step — UIKit views are layer-backed
    /// already, and their `layer` is not optional.
    ///
    /// **`isOpaque` is why this matters on iOS.** A `UIView` is opaque by
    /// default: the compositor takes the view's whole rectangle as covered,
    /// whatever was actually drawn, so an overlay with a few shapes on it
    /// hides the terminal text behind it and shows black everywhere else.
    /// `NSView` has no such default, which is why this is a one-sided fix.
    func vtgUseTransparentLayer() {
        #if os(macOS)
        wantsLayer = true
        layer?.backgroundColor = VTGPlatformColor.clear.cgColor
        #else
        isOpaque = false
        backgroundColor = .clear
        layer.backgroundColor = VTGPlatformColor.clear.cgColor
        #endif
    }
}

extension VTGPlatformColor {
    /// Convert a VTG color into the framework's color for text drawing.
    ///
    /// The macOS path keeps `calibratedRed:`, which is what it has always
    /// used; UIKit has no calibrated initializer and its `init(red:…)` is the
    /// same device-independent sRGB the rest of VTG assumes.
    convenience init(_ color: VTGColor) {
        #if os(macOS)
        self.init(
            calibratedRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
        #else
        self.init(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
        #endif
    }
}

extension VTGColor {
    /// Core Graphics color representation for primitive drawing.
    var cgColor: CGColor {
        CGColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}
#endif
