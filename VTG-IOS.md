# VTG on iOS — what a survey found

**Status:** survey only. Nothing in this repo was changed. Written
2026-09-20 for whoever builds the UIKit arm, so the reading does not have to
happen twice.

**Why anyone wants this:** `ActiveUITerminal` (in `AIResearch/ActiveUI`)
ships a *stand-in* on iPhone and iPad — a view that says "the terminal is
not available in this build". That is true of a local shell and false of the
emulator: iOS forbids spawning a process, not rendering a terminal. The one
thing missing for a real terminal on an iPad is a UIKit VTG view. Plain
`TerminalView` is not the answer — the ruling is **VTG only** (it is
backward compatible with ANSI; 3270 is a separate beast and a separate
control).

## What already exists

- **The UIKit terminal is here and complete.** `Sources/SwiftTerm/iOS/` has
  `iOSTerminalView.swift` (`open class TerminalView: UIScrollView`),
  text input, caret, keyboard accessory, text storage. `Package.swift`
  declares `.iOS(.v14)`.
- **`VectorTerminalView: TerminalView`** is the VTG layer — a subclass, so
  a UIKit `VectorTerminalView` sits on the UIKit `TerminalView` the same way
  the AppKit one sits on the AppKit one.
- **`SwiftUITerminalView.swift` is not to be used** by the ActiveUI side:
  the ActiveUI ground rules are UIKit-only, no SwiftUI.

## The size of the job

In `Sources/SwiftTerm/VectorTerminalGraphics/`:

| | lines |
|---|---|
| Platform-neutral (scene, parsing, geometry, commands, SVG) | **6,905** in 54 files |
| AppKit-gated views | **1,935** in 17 files |
| …of which `LocalProcess*` (no pty on iOS — skip) | 494 |
| …of which `VTGMouse+AppKit` (touch is its own design — skip for now) | 23 |
| **Actually to port** | **~1,420** |

The files to port, largest first:

```
365  VectorTerminalView.swift                    NSCoder NSFont NSLayoutConstraint NSRect NSSize NSView
253  VTGPageView.swift                           NSCoder NSColor NSGraphicsContext NSPoint NSRect NSView
103  VTGOverlayViewBasicPrimitiveDrawing.swift   NSAttributedString NSColor NSFont NSImage
102  VTGTerminalOverlayContainerView.swift       NSCoder NSLayoutConstraint NSRect NSSize NSView
 98  VTGOverlayViewSpriteDrawing.swift           NSImage
 94  VTGOverlayViewShapeDrawing.swift            —
 84  VTGOverlayView.swift                        NSCoder NSColor NSGraphicsContext NSPoint NSRect NSView
 82  VTGOverlayViewRoundedPathDrawing.swift      —
 80  VTGOverlayViewPrimitiveDrawing.swift        —
 78  VTGOverlayViewDrawingHelpers.swift          NSColor
 57  VTGOverlayViewRoundedRectDrawing.swift      —
 42  VTGCanvasSize+AppKit.swift                  NSView
```

Four of the drawing files name no AppKit type at all: they are Core Graphics
against a `CGContext` and compile as they stand once the gate opens.

## Why it is easier than it looks

- **The overlay is already top-left flipped.** `VTGOverlayView` overrides
  `isFlipped` to `true` "so VTG pixel coordinates match terminal
  screenshots" — which is UIKit's native origin. No coordinate flip, no
  y-inversion pass through the drawing code. This is the thing that usually
  makes an AppKit→UIKit drawing port expensive, and it is already paid.
- **The AppKit surface is ~25 sites**, and every one has a direct UIKit
  counterpart: `NSView`→`UIView`, `NSColor`→`UIColor`, `NSImage`→`UIImage`,
  `NSFont`→`UIFont`, `NSRect/NSPoint/NSSize`→`CGRect/CGPoint/CGSize` (they
  are already those types), `NSGraphicsContext.current?.cgContext`→
  `UIGraphicsGetCurrentContext()`, `NSLayoutConstraint` and
  `NSAttributedString` are shared.
- **Two AppKit habits with no UIKit equivalent, both harmless:**
  `wantsLayer = true` (UIKit views are layer-backed already — drop it) and
  `needsDisplay = true` (→ `setNeedsDisplay()`). `hitTest` returns
  `NSView?`/`UIView?` with the same "return nil to pass touches through"
  meaning.

## Suggested shape

**One implementation with platform aliases, not an AppKit/UIKit twin.** A
twin doubles every future VTG primitive; these files are 90% arithmetic and
`CGContext` calls that do not care which framework drew the rectangle. That
means:

1. A small `VTGPlatformTypes.swift`: `typealias VTGView`, `VTGColor`,
   `VTGImage`, `VTGFont`, plus a `currentCGContext()` helper, defined per
   framework.
2. Change `#if os(macOS)` to `#if os(macOS) || os(iOS)` on the twelve files
   above, and substitute the aliases.
3. Leave `LocalProcess*` AppKit-gated as they are — a pty is exactly what
   iOS does not have.

**macOS cannot break.** VGTerm, OmegaCLIDE and Freebird all ride this
renderer, so the substitution should be mechanical and reviewed as such: no
logic edits smuggled in, the macOS build and SwiftTerm's own tests green
before and after.

## What the consumer needs from the finished view

`ActiveUITerminal`'s iOS backend (to be written on the ActiveUI side) uses
exactly this surface, all of which the AppKit `VectorTerminalView` already
has: `feed(byteArray:)`, `getTerminal()`, `terminalDelegate` (for
`send(source:data:)`, `sizeChanged`, `setTerminalTitle`,
`hostCurrentDirectoryUpdate`, `bell`), `font`, `nativeForegroundColor`,
`nativeBackgroundColor`, `caretColor`, `selectedTextBackgroundColor`,
`installPalette(colors:)`, `setCursorStyle(_:)`, and the VTG members
`feedVTG(_:)`, `areGraphicsLayersVisible` / `setGraphicsLayersVisible(_:)`,
`vectorGraphicsResponsesMuted`, `resetVectorGraphicsSession()`,
`isVectorGraphicsPageModeActive`, `notifyVTGResizeIfNeeded(force:)`.

There is no process on iOS, so `LocalProcessVectorTerminalView` has no iOS
form: the app feeds bytes in and gets typed bytes back, and whatever is on
the other end — a socket, ssh, a recorded stream — is the app's business.

**A live test target already exists:** Bobby's z/OS simulator listens on
`127.0.0.1:3271` (line protocol), and an iOS simulator reaches the host's
loopback directly.
