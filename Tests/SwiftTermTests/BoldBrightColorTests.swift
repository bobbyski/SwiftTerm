//
//  BoldBrightColorTests.swift
//
//  `useBrightColors` is the palette-wide switch; `boldUsesBrightColors` only
//  governs bold promotion. Conflating them recolors every explicitly-bright
//  cell on screen, which is what these tests pin down.
//

#if os(macOS)
import Foundation
import Testing
import AppKit

@testable import SwiftTerm

@MainActor
@Suite("Bold and bright color policy")
struct BoldBrightColorTests {

    private func makeView() -> TerminalView {
        TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    }

    /// The color the palette resolves for an ANSI index, as drawing would.
    private func color(_ view: TerminalView, ansi: UInt8, isBold: Bool) -> NSColor {
        view.mapColor(
            color: .ansi256(code: ansi),
            isFg: true,
            isBold: isBold,
            useBrightColors: view.useBrightColors
        )
    }

    @Test("A program's explicit bright color survives bold promotion being off")
    func explicitBrightSurvivesWithoutPromotion() {
        let view = makeView()
        let brightWithPromotion = color(view, ansi: 11, isBold: false)

        view.boldUsesBrightColors = false
        let brightWithoutPromotion = color(view, ansi: 11, isBold: false)

        #expect(brightWithPromotion == brightWithoutPromotion,
                "bright yellow must stay bright yellow — this is the powerline-prompt regression")
    }

    @Test("Bold promotion moves 0-7 into 8-15, and only when enabled")
    func boldPromotionIsItsOwnSwitch() {
        let view = makeView()

        view.boldUsesBrightColors = true
        #expect(color(view, ansi: 3, isBold: true) == color(view, ansi: 11, isBold: false),
                "bold yellow promotes to bright yellow")

        view.boldUsesBrightColors = false
        #expect(color(view, ansi: 3, isBold: true) == color(view, ansi: 3, isBold: false),
                "with promotion off, bold keeps its own color")
    }

    @Test("The palette-wide switch still folds bright down to normal")
    func paletteWideSwitchStillFolds() {
        let view = makeView()
        view.useBrightColors = false

        let folded = view.mapColor(color: .ansi256(code: 11), isFg: true, isBold: false,
                                   useBrightColors: false)
        let normal = view.mapColor(color: .ansi256(code: 3), isFg: true, isBold: false,
                                   useBrightColors: false)
        #expect(folded == normal)
    }

    @Test("Both switches default to the long-standing behavior")
    func defaultsAreUnchanged() {
        let view = makeView()
        #expect(view.useBrightColors)
        #expect(view.boldUsesBrightColors)
    }
}
#endif
