#if os(macOS)
//
//  WindowCGBaselineTests.swift
//  SwiftTerm — WINDOW_PLAN.md 0.2, 0.4 and 1.10 on CoreGraphics
//
//  The real terminal view's draw pass, captured with cacheDisplay: text, the
//  layer-0 hook and the overlay view, as AppKit draws them.
//

import AppKit
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
@Suite("Window plan: CoreGraphics baseline and mask", .serialized)
struct WindowCGBaselineTests {
    private let esc = "\u{1b}"
    private func vtg(_ body: String) -> String { "\(esc)_VTG;\(body)\(esc)\\" }

    /// A view with a full-width box-drawing line on row 1, and a blue bar
    /// over it on `layer`.
    private func makeView(layer: Int, occlude: Bool) -> VectorTerminalView {
        let view = VectorTerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        view.vtgResponseHandler = { _ in }
        view.nativeForegroundColor = .white
        view.nativeBackgroundColor = .black
        let cell = view.currentVTGCellSize()!
        view.feed(text: "\(esc)[2;1H" + String(repeating: "\u{2588}", count: 20))
        view.feedVTG(Array(((occlude ? vtg("layerOcclude,layer=\(layer),by=ink") : "")
            + vtg("rect,id=bar,x=0,y=0,w=400,h=\(2 * cell.height),stroke=none,fill=#0000ff,layer=\(layer)")).utf8))
        view.updateDisplay(notifyAccessibility: false)
        return view
    }

    /// The color at the middle of a cell, as AppKit draws the view.
    private func sample(_ view: VectorTerminalView, col: Int, row: Int) -> NSColor? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let cell = view.currentVTGCellSize()!
        let scale = Double(rep.pixelsWide) / Double(view.bounds.width)
        return rep.colorAt(x: Int((Double(col) + 0.5) * cell.width * scale),
                           y: Int((Double(row) + 0.5) * cell.height * scale))?.usingColorSpace(.sRGB)
    }

    private func isBlue(_ color: NSColor?) -> Bool {
        guard let color else { return false }
        return color.blueComponent > 0.7 && color.redComponent < 0.3 && color.greenComponent < 0.3
    }

    private func isWhite(_ color: NSColor?) -> Bool {
        guard let color else { return false }
        return color.redComponent > 0.7 && color.greenComponent > 0.7 && color.blueComponent > 0.7
    }

    @Test("Finding C: on CoreGraphics, layer 0 is drawn upside down (pre-existing, not fixed)")
    func findingC() {
        // A bar at the top of the canvas, on layer 0, with no text anywhere.
        let view = VectorTerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        view.vtgResponseHandler = { _ in }
        view.nativeBackgroundColor = .black
        let cell = view.currentVTGCellSize()!
        view.feedVTG(Array(vtg("rect,id=bar,x=0,y=0,w=400,h=\(cell.height),stroke=none,fill=#0000ff,layer=0").utf8))
        view.updateDisplay(notifyAccessibility: false)
        let rows = view.getTerminal().rows
        // The terminal view is not flipped and the layer-0 hook draws VTG's
        // top-left coordinates into it as they are: the bar lands at the bottom.
        #expect(!isBlue(sample(view, col: 5, row: 0)), "not at the top, where VTG put it")
        #expect(isBlue(sample(view, col: 5, row: rows - 1)), "at the bottom instead")
    }

    @Test("Overlay layers float over the text on CoreGraphics (the reported bug)")
    func overlayFloats() {
        let view = makeView(layer: 1, occlude: false)
        #expect(isBlue(sample(view, col: 5, row: 1)))
    }

    @Test("1.10 on CoreGraphics: a masked overlay layer lets the text show, and still draws on blank rows")
    func maskedOverlayOnCoreGraphics() {
        let view = makeView(layer: 1, occlude: true)
        #expect(isWhite(sample(view, col: 5, row: 1)), "the glyph's ink shows through the masked layer")
        #expect(isBlue(sample(view, col: 5, row: 0)), "no ink on row 0, so the layer still draws there")
    }

    @Test("Finding D: on CoreGraphics, layer -1 is not drawn at all (pre-existing)")
    func findingD() {
        let view = VectorTerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        view.vtgResponseHandler = { _ in }
        view.nativeBackgroundColor = .black
        view.feedVTG(Array(vtg("rect,id=under,x=0,y=0,w=400,h=200,stroke=none,fill=#00ff00,layer=-1").utf8))
        view.updateDisplay(notifyAccessibility: false)
        let color = sample(view, col: 5, row: 3)
        #expect((color?.greenComponent ?? 0) < 0.3, "the under-text plane is a Metal-path feature on the Mac")
    }
}
#endif
