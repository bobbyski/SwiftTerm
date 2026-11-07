#if os(macOS)
//
//  WindowRasterBitmapTests.swift
//  SwiftTerm — WINDOW_PLAN.md Phase 5 on the Mac (5.4, 5.5)
//

import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
@Suite("Window plan: raster text on the Mac", .serialized)
struct WindowRasterBitmapTests {
    private let esc = "\u{1b}"
    private func vtg(_ body: String) -> String { "\(esc)_VTG;\(body)\(esc)\\" }

    /// The framebuffer as the overlay would draw it, as RGBA rows from the top.
    private func pixels(_ view: VectorTerminalView) -> (bytes: [UInt8], width: Int) {
        view.applyVTGRaster()
        let width = Int(view.bounds.width), height = Int(view.bounds.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            // Top-left origin, as the overlay draws.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            view.vtgRasterBitmap.draw(in: context, bounds: view.bounds)
        }
        return (bytes, width)
    }

    private func alpha(_ image: (bytes: [UInt8], width: Int), _ view: VectorTerminalView, col: Int, row: Int) -> UInt8 {
        let cell = view.currentVTGCellSize()!
        let x = Int((Double(col) + 0.5) * cell.width), y = Int((Double(row) + 0.5) * cell.height)
        return image.bytes[(y * image.width + x) * 4 + 3]
    }

    @Test("Text erases raster drawing, drawing scrolls with the text, and the terminal stops reporting after")
    func framebuffer() {
        let view = VectorTerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 240))
        view.vtgResponseHandler = { _ in }
        guard let cell = view.currentVTGCellSize() else { return }
        view.feedVTG(Array((vtg("rasterMode,enabled=1,text=erases")
                            + vtg("rect,id=band,x=0,y=\(2 * cell.height),w=400,h=\(cell.height),fill=#ff0000")).utf8))
        #expect(view.getTerminal().cellWriteObserver != nil, "the canvas is listening")
        view.feed(text: "\(esc)[3;4H    ")
        var image = pixels(view)
        #expect(alpha(image, view, col: 1, row: 2) == 255, "band where nothing was written")
        #expect(alpha(image, view, col: 4, row: 2) == 0, "erased by default-colored spaces")
        #expect(view.vtgSession.controller.scene.primitives.isEmpty, "nothing retained")

        let rows = view.getTerminal().rows
        view.feed(text: "\(esc)[\(rows);1H\n\n")
        image = pixels(view)
        #expect(alpha(image, view, col: 1, row: 0) == 255, "the band scrolled up two rows")
        #expect(alpha(image, view, col: 4, row: 0) == 0, "with its erased cells")
        #expect(alpha(image, view, col: 1, row: 2) == 0, "and left its old row")

        view.feedVTG(Array(vtg("rasterMode,enabled=0").utf8))
        #expect(view.getTerminal().cellWriteObserver == nil, "no reporting once the mode is off")
        #expect(view.vtgOverlayView.rasterBitmap == nil)
    }
}
#endif
