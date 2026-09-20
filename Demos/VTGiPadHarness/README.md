# VTGiPadHarness

A place to watch SwiftTerm's VTG view draw on iPadOS. Not a product: three
tabs, no input, no network.

    Text      ordinary terminal output — colours, attributes, the cursor
    Graphics  retained VTG primitives in the overlay, over live text
    Page      a VTG Page Mode page, built off screen and shown in one step

There is no process behind the terminal, because iOS does not allow one.
Every byte arrives through `feed(byteArray:)`, and the scenes are written as
escape sequences rather than SDK calls — the same bytes a program on the far
end of an SSH connection would send.

## Build and run

The project is the source: it is maintained in Xcode, and there is no
XcodeGen spec to regenerate it from.

    xcodebuild -project Demos/VTGiPadHarness/VTGiPadHarness.xcodeproj \
        -scheme VTGiPadHarness \
        -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
        CODE_SIGNING_ALLOWED=NO build

    xcrun simctl install booted Demos/VTGiPadHarness/Build/Products/Debug-iphonesimulator/VTGiPadHarness.app
    xcrun simctl launch booted com.vectorterminal.VTGiPadHarness

`xcrun simctl launch --console-pty` instead of `launch` prints the harness's
own diagnostics: the view size, the terminal grid, the cell size, and every
VTG reply the view produced.
