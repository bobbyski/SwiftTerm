#if os(macOS) && canImport(MetalKit)
//
//  WindowMetalPixelTests.swift
//  SwiftTerm — WINDOW_PLAN.md 0.2, 0.4, 1.10 and 4.2 on Metal
//
//  Real Metal frames, captured through the renderer's test seam
//  (`captureNextFrame`). The Metal pass draws the text and layers -1 and 0;
//  layers 1…4 are the CoreGraphics overlay view above it, tested elsewhere.
//

import AppKit
import Metal
import Testing

@testable import SwiftTerm

@MainActor
@Suite("Window plan: Metal pixels", .serialized)
struct WindowMetalPixelTests {
    private let esc = "\u{1b}"
    private func vtg(_ body: String) -> String { "\(esc)_VTG;\(body)\(esc)\\" }

    private struct Frame {
        let bytes: [UInt8]
        let width: Int
        let scale: Double
        let cell: (width: Double, height: Double)

        /// (r, g, b) at the middle of a cell; the capture is BGRA.
        func color(col: Int, row: Int) -> (r: Int, g: Int, b: Int) {
            let x = Int((Double(col) + 0.5) * cell.width * scale)
            let y = Int((Double(row) + 0.5) * cell.height * scale)
            let i = (y * width + x) * 4
            return (Int(bytes[i + 2]), Int(bytes[i + 1]), Int(bytes[i]))
        }
    }

    private func metalView() throws -> VectorTerminalView? {
        guard MTLCreateSystemDefaultDevice() != nil else { return nil }
        let view = VectorTerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        view.vtgResponseHandler = { _ in }
        view.nativeForegroundColor = .white
        view.nativeBackgroundColor = .black
        try view.setUseMetal(true)
        return view
    }

    private func capture(_ view: TerminalView) -> Frame? {
        view.updateDisplay(notifyAccessibility: false)
        guard let mtk = view.metalView, let renderer = view.metalRenderer, let cell = (view as? VectorTerminalView)?.currentVTGCellSize() ?? Optional((width: Double(view.cellDimension.width), height: Double(view.cellDimension.height))) else {
            return nil
        }
        mtk.framebufferOnly = false
        let done = DispatchSemaphore(value: 0)
        var frame: Frame?
        renderer.captureNextFrame = { bytes, width, _ in
            frame = Frame(bytes: bytes, width: width, scale: Double(width) / Double(view.bounds.width), cell: cell)
            done.signal()
        }
        mtk.draw()
        _ = done.wait(timeout: .now() + 3)
        return frame
    }

    private func isBlue(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.b > 180 && c.r < 80 && c.g < 80 }
    private func isGreen(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.g > 150 && c.r < 80 && c.b < 80 }
    private func isWhite(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.r > 180 && c.g > 180 && c.b > 180 }
    private func isWindowRed(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.r > 150 && c.g < 60 && c.b < 60 }

    /// Full blocks along row 1, and a blue bar over rows 0…1 on `layer`.
    private func barOverText(layer: Int, occlude: Bool) throws -> Frame? {
        guard let view = try metalView(), let cell = view.currentVTGCellSize() else { return nil }
        view.feed(text: "\(esc)[2;1H" + String(repeating: "\u{2588}", count: 20))
        view.feedVTG(Array(((occlude ? vtg("layerOcclude,layer=\(layer),by=ink") : "")
            + vtg("rect,id=bar,x=0,y=0,w=400,h=\(2 * cell.height),stroke=none,fill=#0000ff,layer=\(layer)")).utf8))
        return capture(view)
    }

    @Test("0.2 on Metal: Finding A — layer 0 is drawn over the text")
    func findingA() throws {
        guard let frame = try barOverText(layer: 0, occlude: false) else { return }
        #expect(isBlue(frame.color(col: 5, row: 1)), "the bar covers the glyphs")
        #expect(isBlue(frame.color(col: 5, row: 0)))
    }

    @Test("1.10 on Metal: a masked layer 0 lets the text show, and still draws on blank rows")
    func maskedTextPlane() throws {
        guard let frame = try barOverText(layer: 0, occlude: true) else { return }
        #expect(isWhite(frame.color(col: 5, row: 1)), "the glyphs' ink shows")
        #expect(isBlue(frame.color(col: 5, row: 0)), "no ink on row 0")
    }

    @Test("0.4 on Metal, Finding E: layer -1 is drawn over colored cell backgrounds, under the glyphs")
    func underText() throws {
        guard let view = try metalView() else { return }
        view.feed(text: "\(esc)[3;1H\(esc)[48;2;200;0;0m" + String(repeating: " ", count: 10) + "\(esc)[0m")
        view.feedVTG(Array(vtg("rect,id=under,x=0,y=0,w=400,h=200,stroke=none,fill=#00ff00,layer=-1").utf8))
        guard let frame = capture(view) else { return }
        let colored = frame.color(col: 5, row: 2)
        print("Metal 0.4: layer -1 over a colored cell = \(colored)")
        // Metal draws cell backgrounds, then layer -1, then glyphs; GL draws
        // layer -1 before the backgrounds. Pre-existing; recorded, not changed.
        #expect(isGreen(colored), "on Metal the colored cell does not cover layer -1")
        #expect(isGreen(frame.color(col: 5, row: 5)), "a default cell shows it")
    }

    @Test("4.2: a VTG window's child view draws its content on Metal")
    func windowOnMetal() throws {
        guard let view = try metalView() else { return }
        view.feedVTG(Array((vtg("windowCreate,id=a,cols=10,rows=3,x=50,y=50,border=0,shadow=0")
                            + vtg("windowSelect,id=a") + "\(esc)[48;2;200;0;0m" + String(repeating: " ", count: 30)
                            + vtg("windowSelect,id=root")).utf8))
        guard let container = view.subviews.compactMap({ $0 as? VTGWindowContainerView }).first else {
            Issue.record("no window")
            return
        }
        let child = container.terminalView
        #expect(child.rendererMode == .metal, "the window uses Metal because the root does")
        guard let frame = capture(child) else { return }
        #expect(isWindowRed(frame.color(col: 2, row: 1)))
    }

    @Test("4.6 on Metal: a window without focus draws no cursor; focusing it brings the cursor back")
    func cursorFollowsFocus() throws {
        guard let view = try metalView() else { return }
        view.feedVTG(Array(vtg("windowCreate,id=a,cols=10,rows=3,x=50,y=50,border=0,shadow=0").utf8))
        guard let child = view.subviews.compactMap({ $0 as? VTGWindowContainerView }).first?.terminalView else {
            Issue.record("no window")
            return
        }
        /// The brightest pixel in the cursor's cell, (0, 0).
        func brightest() -> Int {
            guard let frame = capture(child) else { return -1 }
            var best = 0
            let cellWidth = Int(frame.cell.width * frame.scale), cellHeight = Int(frame.cell.height * frame.scale)
            for y in 0..<cellHeight {
                for x in 0..<cellWidth {
                    let i = (y * frame.width + x) * 4
                    best = max(best, Int(frame.bytes[i]) + Int(frame.bytes[i + 1]) + Int(frame.bytes[i + 2]))
                }
            }
            return best
        }
        #expect(brightest() < 60, "no focus, no cursor")
        view.feedVTG(Array(vtg("windowFocus,id=a").utf8))
        #expect(brightest() > 300, "focused: the cursor is drawn")
    }
}
#endif
