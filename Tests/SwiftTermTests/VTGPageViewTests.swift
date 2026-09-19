#if os(macOS)
//
//  VTGPageViewTests.swift
//
//  VTG Page Mode end to end on a real terminal view: bytes in through the
//  terminal parser, pixels out of the page view.
//

import AppKit
import Testing

@testable import SwiftTerm

@MainActor
final class VTGPageViewTests {
    private let esc = "\u{1B}"

    private func feed(_ view: VectorTerminalView, _ commands: String...) {
        for command in commands {
            view.feedVTG(Data("\(esc)_VTG;\(command)\(esc)\\".utf8))
        }
    }

    /// Render the page view into an RGBA bitmap, top-left origin.
    private func render(_ view: VectorTerminalView) throws -> (width: Int, height: Int, pixels: [UInt8]) {
        let width = Int(view.bounds.width), height = Int(view.bounds.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            // Flip to the view's top-left origin.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            let page = try #require(view.vtgPageView.page)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            view.vtgPageView.draw(page: page, in: context, bounds: view.bounds)
            NSGraphicsContext.restoreGraphicsState()
        }
        return (width, height, pixels)
    }

    private func pixel(_ image: (width: Int, height: Int, pixels: [UInt8]), _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * image.width + x) * 4
        return (image.pixels[i], image.pixels[i + 1], image.pixels[i + 2], image.pixels[i + 3])
    }

    @Test func pageStaysOffScreenUntilShown() {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        feed(view, "pageBegin,id=t", "pageOpen,id=p1,bg=#ff0000")
        #expect(view.isVectorGraphicsPageModeActive)
        #expect(view.vtgPageView.isHidden)
        #expect(view.vtgPageView.page == nil)

        feed(view, "pageShow")
        #expect(!view.vtgPageView.isHidden)
        #expect(view.vtgPageView.page?.id == "p1")

        view.setGraphicsLayersVisible(false)
        #expect(view.vtgPageView.isHidden, "the graphics toggle hides the page too")
        view.setGraphicsLayersVisible(true)

        view.dismissVectorGraphicsPage()
        #expect(!view.isVectorGraphicsPageModeActive)
        #expect(view.vtgPageView.isHidden)
    }

    @Test func pageDrawsBackgroundLayersAndScroll() throws {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        feed(
            view,
            "pageBegin,id=t",
            "pageOpen,id=p1,bg=#0000ff,h=400",
            "rect,id=r,x=10,y=210,w=40,h=40,fill=#00ff00,stroke=none",
            "pageLayerAdd,id=hud,z=9,scroll=fixed",
            "rect,id=bar,x=0,y=0,w=200,h=6,fill=#ff0000,stroke=none,layer=hud",
            "pageShow",
            "pageScroll,y=200"
        )
        let image = try render(view)
        // Page background.
        // Channels are compared by dominance: the bitmap is device RGB, so an
        // sRGB primary picks up a little of its neighbours in conversion.
        let background = pixel(image, 150, 60)
        #expect(Int(background.b) > Int(background.r) + 150 && Int(background.b) > Int(background.g) + 100)
        // The rect at page y=210 is at view y=10 once scrolled by 200.
        let rect = pixel(image, 30, 30)
        #expect(Int(rect.g) > Int(rect.r) + 100 && Int(rect.g) > Int(rect.b) + 100)
        // The fixed HUD layer ignores the scroll.
        let bar = pixel(image, 100, 2)
        #expect(Int(bar.r) > Int(bar.g) + 100 && Int(bar.r) > Int(bar.b) + 100)
    }

    @Test func transparentPageLeavesUntouchedPixelsClear() throws {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        feed(view, "pageBegin", "pageOpen,id=p1,bg=none", "circle,id=c,cx=50,cy=50,r=20,fill=#ffffff", "pageShow")
        let image = try render(view)
        #expect(pixel(image, 150, 80).a == 0, "the terminal shows through a transparent page")
        #expect(pixel(image, 50, 50).a > 200)
    }

    @Test func richTextRendersGlyphs() throws {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        feed(
            view,
            "pageBegin",
            "pageOpen,id=p1,bg=none",
            "textStyle,id=big,size=40,weight=bold,color=#ffffff",
            "attrText,id=t,x=10,y=10,style=big;-:5:HELLO",
            "pageShow"
        )
        let image = try render(view)
        var inked = 0
        for y in 10..<60 {
            for x in 10..<200 where pixel(image, x, y).a > 128 {
                inked += 1
            }
        }
        #expect(inked > 300, "only \(inked) pixels drawn for 40pt HELLO")
        #expect(pixel(image, 280, 90).a == 0)
    }

    @Test func viewportAndOverTextStacking() throws {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        feed(view, "pageBegin,over=text", "pageOpen,id=p1,bg=#ffffff", "pageViewport,x=50,y=20,w=60,h=40", "pageShow")
        let subviews = view.subviews
        let pageIndex = try #require(subviews.firstIndex { $0 === view.vtgPageView })
        let overlayIndex = try #require(subviews.firstIndex { $0 === view.vtgOverlayView })
        #expect(pageIndex < overlayIndex, "over=text puts the page beneath the VTG overlay")

        let image = try render(view)
        #expect(pixel(image, 70, 30).a > 200)
        #expect(pixel(image, 20, 30).a == 0, "outside the viewport")
        #expect(pixel(image, 150, 30).a == 0, "outside the viewport")
    }

    @Test func promptMarkAndResetEndPageMode() {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        feed(view, "pageBegin", "pageOpen,id=p1", "pageShow")
        view.feed(text: "\(esc)]133;C\u{7}")
        #expect(view.isVectorGraphicsPageModeActive, "output-start is not a prompt")
        view.feed(text: "\(esc)]133;D;0\u{7}")
        #expect(!view.isVectorGraphicsPageModeActive, "command-end means the owner has gone")

        feed(view, "pageBegin", "pageOpen,id=p1", "pageShow")
        view.feed(text: "\(esc)c")
        #expect(!view.isVectorGraphicsPageModeActive, "RIS ends page mode")
    }

    /// Rasterize whatever asks to be, so these tests are about the cache
    /// rather than about how fast this machine draws circles.
    private func alwaysRasterize<T>(_ body: () throws -> T) rethrows -> T {
        let previous = VTGPageView.rasterizeAboveSeconds
        VTGPageView.rasterizeAboveSeconds = -1
        defer { VTGPageView.rasterizeAboveSeconds = previous }
        return try body()
    }

    /// A layer is only rasterized when drawing it costs more than blitting
    /// it: a cheap background stays on the direct path even when it asks.
    @Test func cheapLayersAreNotRasterized() throws {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        feed(
            view,
            "pageBegin",
            "pageOpen,id=p1,bg=#000000",
            "pageLayerAdd,id=bg,cache=1",
            "rect,id=one,x=0,y=0,w=20,h=20,fill=#ff0000,stroke=none,layer=bg",
            "pageShow"
        )
        _ = try render(view)
        _ = try render(view)
        #expect(view.vtgPageView.lastCacheMisses == 0)
        #expect(view.vtgPageView.lastCacheHits == 0)
    }

    /// A cached layer must look exactly like the same layer drawn directly.
    @Test func cachedLayersMatchDirectDrawingAndInvalidate() throws {
        func scene(cache: Bool) throws -> VectorTerminalView {
            let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
            feed(
                view,
                "pageBegin",
                "pageOpen,id=p1,bg=#000000",
                "pageLayerAdd,id=bg,cache=\(cache ? 1 : 0)",
                "rect,id=top,x=0,y=0,w=200,h=20,fill=#ff0000,stroke=none,layer=bg",
                "circle,id=dot,cx=150,cy=90,r=15,fill=#00ff00,layer=bg",
                "styledText,id=t,x=10,y=40,size=24,color=#ffffff,layer=bg;Cache",
                "pageShow"
            )
            return view
        }
        let direct = try render(try scene(cache: false))
        let view = try scene(cache: true)
        try alwaysRasterize {
            // The first pass measures the layer; the second rasterizes it.
            _ = try render(view)
            let cached = try render(view)
            #expect(view.vtgPageView.lastCacheMisses == 1)

            var differing = 0
            for index in stride(from: 0, to: direct.pixels.count, by: 4)
                where abs(Int(direct.pixels[index]) - Int(cached.pixels[index])) > 8
                    || abs(Int(direct.pixels[index + 1]) - Int(cached.pixels[index + 1])) > 8 {
                differing += 1
            }
            #expect(differing < 20, "\(differing) pixels differ between cached and direct drawing")
            // Red bar at the top, not the bottom: the cache is not upside down.
            #expect(pixel(cached, 100, 5).r > 200)
            #expect(pixel(cached, 100, 115).r < 30)

            _ = try render(view)
            #expect(view.vtgPageView.lastCacheHits == 1, "an unchanged layer is reused")

            feed(view, "rect,id=top,x=0,y=0,w=200,h=20,fill=#0000ff,stroke=none,layer=bg")
            _ = try render(view)
            #expect(view.vtgPageView.lastCacheHits == 0, "a changed layer is measured again")
            let changed = try render(view)
            #expect(view.vtgPageView.lastCacheMisses == 1, "then rasterized again")
            #expect(pixel(changed, 100, 5).b > 200)
        }
    }

    /// A background borrowed by reference is one scene, rasterized once for
    /// whichever page shows it.
    @Test func borrowedBackgroundIsRasterizedOnce() throws {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        feed(
            view,
            "pageBegin",
            "pageOpen,id=f1",
            "pageLayerAdd,id=bg,z=0,cache=1",
            "rect,id=sky,x=0,y=0,w=200,h=120,fill=#3366ff,stroke=none,layer=bg",
            "pageShow"
        )
        try alwaysRasterize {
            _ = try render(view)
            _ = try render(view)
            #expect(view.vtgPageView.lastCacheMisses == 1)
            feed(
                view,
                "pageOpen,id=f2",
                "pageLayerCopy,id=bg,from=f1,layer=bg",
                "circle,id=ship,cx=50,cy=50,r=5,fill=#ffffff",
                "pageShow"
            )
            let image = try render(view)
            #expect(view.vtgPageView.lastCacheHits == 1, "the second page reuses the first page's raster")
            #expect(view.vtgPageView.lastCacheMisses == 0)
            #expect(pixel(image, 150, 100).b > 200)
            #expect(pixel(image, 50, 50).r > 200)
        }
    }

    /// The shell example in Escape codes.md, byte for byte.
    @Test func documentedShellExampleWorks() throws {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        feed(
            view,
            "pageBegin,id=demo",
            "pageOpen,id=p1,bg=#101018e0",
            "textStyle,id=h1,font=Georgia,size=32,weight=bold,color=#ffffff",
            "styledText,id=title,x=40,y=40,style=h1;Page Mode",
            "textBox,id=body,x=40,y=100,w=420;-:63:Drawn off screen, shown in one step. The terminal runs beneath.",
            "pageShow"
        )
        let page = try #require(view.vtgPageView.page)
        let ids = page.layer(id: "1")?.scene.primitives.map(\.id)
        #expect(ids == ["title", "body"])
        guard case .richText(let body) = try #require(page.layer(id: "1")?.scene.primitives.last) else { return }
        #expect(body.plainText == "Drawn off screen, shown in one step. The terminal runs beneath.")
        feed(view, "pageEnd")
        #expect(!view.isVectorGraphicsPageModeActive)
    }

    @Test func pageEventsReachTheHost() {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var responses: [String] = []
        view.vtgResponseHandler = { responses.append($0) }
        feed(view, "pageBegin,id=s", "pageOpen,id=p1", "pageShow")
        view.dismissVectorGraphicsPage()
        #expect(responses.contains("\(esc)_VTG;pageShown,id=p1,slot=A\(esc)\\"))
        #expect(responses.last == "\(esc)_VTG;pageEnded,id=s,reason=host\(esc)\\")
    }
}
#endif
