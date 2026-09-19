#if os(macOS)
import AppKit
import Testing

@testable import SwiftTerm

/// Not an assertion of speed — printed measurements, so the cost of
/// compositing a page is a number someone can look at rather than a guess.
@MainActor
struct VTGPagePerformanceSmoke {
    private func measure(pageHeight: Int, objects: Int, cache: Bool) throws -> Double {
        let view = VectorTerminalView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        func feed(_ command: String) {
            view.feedVTG(Data("\u{1B}_VTG;\(command)\u{1B}\\".utf8))
        }
        feed("pageBegin")
        feed("pageOpen,id=p1,bg=#101018,h=\(pageHeight)")
        feed("pageLayerAdd,id=bg,z=0,cache=\(cache ? 1 : 0)")
        for index in 0..<objects {
            feed("circle,id=s\(index),cx=\(index * 7 % 1200),cy=\(index * 9 % pageHeight),r=3,fill=#ffffff,layer=bg")
        }
        feed("pageLayerAdd,id=fg,z=1")
        feed("rect,id=ship,x=100,y=100,w=40,h=20,fill=#5eead4,stroke=none,layer=fg")
        feed("pageShow")

        let page = try #require(view.vtgPageView.page)
        var pixels = [UInt8](repeating: 0, count: 1200 * 800 * 4)
        var perFrame = 0.0
        let space = CGColorSpaceCreateDeviceRGB()
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1200, height: 800,
                                    bitsPerComponent: 8, bytesPerRow: 1200 * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            view.vtgPageView.draw(page: page, in: context, bounds: view.bounds)  // warm
            let start = Date()
            for _ in 0..<40 {
                view.vtgPageView.draw(page: page, in: context, bounds: view.bounds)
            }
            perFrame = Date().timeIntervalSince(start) / 40 * 1000
            NSGraphicsContext.restoreGraphicsState()
        }
        return perFrame
    }

    @Test(.disabled("measurement, run by hand")) func compositeCost() throws {
        for (height, objects) in [(800, 400), (800, 4000), (4000, 400), (4000, 4000)] {
            let cached = try measure(pageHeight: height, objects: objects, cache: true)
            let direct = try measure(pageHeight: height, objects: objects, cache: false)
            print(String(format: "page %4d tall, %4d objects:  cached %6.2f ms   direct %6.2f ms",
                         height, objects, cached, direct))
        }
    }
}
#endif
