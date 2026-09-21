#if os(macOS) || os(iOS)
import CoreGraphics
import Foundation
import Testing

@testable import SwiftTerm

/// The same pixels on both platforms (IPAD_PLAN.md, item 2.8).
///
/// `VTGOverlayView` compiles for AppKit and UIKit from one source, and this
/// suite is what makes "one source" a claim that can fail: it draws a scene
/// into a bitmap through the overlay and reads pixels back, with identical
/// expectations on macOS (`swift test`) and on an iPad simulator
/// (`xcodebuild test`). A coordinate flip, a colour-space slip or a platform
/// branch that draws differently shows up here as a wrong pixel.
@MainActor
@Suite("VTG overlay pixels")
struct VTGOverlayPixelTests {
    private let width = 120
    private let height = 60

    @Test("Shapes land where VTG says, top-left origin")
    func shapesLandAtTheirCoordinates() throws {
        let scene = VTGGraphicsScene()
        scene.apply(command("rect", ["id": "r", "layer": "1", "x": "10", "y": "10", "w": "40", "h": "20",
                                     "stroke": "none", "fill": "#ff0000"]))
        scene.apply(command("circle", ["id": "c", "layer": "1", "cx": "90", "cy": "40", "r": "10",
                                       "stroke": "none", "fill": "#00ff00"]))
        let pixels = try render(scene)
        print("VTG overlay pixels: #ff0000 drew as \(pixels.rgba(x: 20, y: 15)), #00ff00 as \(pixels.rgba(x: 90, y: 40))")

        // Inside the rectangle — near the top, because VTG's origin is top-left.
        #expect(pixels.color(x: 20, y: 15) == .red)
        #expect(pixels.color(x: 45, y: 25) == .red)
        // Inside the circle.
        #expect(pixels.color(x: 90, y: 40) == .green)
        // Outside everything: the overlay is transparent, not black.
        #expect(pixels.color(x: 5, y: 5) == .clear)
        #expect(pixels.color(x: 60, y: 50) == .clear)
        // A rectangle drawn at the top must not appear at the bottom, which
        // is what an unflipped context would do.
        #expect(pixels.color(x: 20, y: height - 15) == .clear)
    }

    @Test("Layer alpha is applied, not ignored")
    func layerAlphaIsApplied() throws {
        let scene = VTGGraphicsScene()
        scene.apply(command("rect", ["id": "r", "layer": "1", "x": "0", "y": "0", "w": "120", "h": "60",
                                     "stroke": "none", "fill": "#0000ff80"]))
        let pixels = try render(scene)
        let sample = pixels.rgba(x: 60, y: 30)
        // Half-transparent blue: alpha about 128, and blue by a wide margin.
        #expect(abs(Int(sample.a) - 128) <= 2)
        #expect(Int(sample.b) > 3 * Int(sample.r) && Int(sample.b) > 3 * Int(sample.g))
    }

    // MARK: - Rendering

    private func render(_ scene: VTGGraphicsScene) throws -> Pixels {
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            // Top-left origin, as the view's own draw pass sees it. Memory row
            // 0 is then VTG's y = 0.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            vtgPushDrawingContext(context)
            VTGOverlayView(frame: CGRect(x: 0, y: 0, width: width, height: height)).draw(
                scene: scene,
                plane: nil,
                in: context,
                bounds: CGRect(x: 0, y: 0, width: width, height: height)
            )
            vtgPopDrawingContext()
            return true
        }
        try #require(drawn, "could not create a bitmap context")
        return Pixels(bytes: buffer, width: width)
    }

    private func command(_ name: String, _ parameters: [String: String]) -> VectorTerminalGraphicsCommand {
        VectorTerminalGraphicsCommand(name: name, parameters: parameters, payload: nil)
    }
}

/// An RGBA bitmap, read back.
private struct Pixels {
    enum Color: Equatable {
        case red, green, clear, other
    }

    let bytes: [UInt8]
    let width: Int

    func rgba(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let index = (y * width + x) * 4
        return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
    }

    /// A tolerant classification, because these tests are about geometry.
    ///
    /// **Colour is not exact, and that is a finding, not noise.** `VTGColor`
    /// becomes a `CGColor` through `CGColor(red:green:blue:alpha:)`, which is
    /// not sRGB on macOS: drawn into an sRGB bitmap, `#ff0000` comes out as
    /// (255, 38, 0). That predates the iPad port, and correcting it would
    /// change what every Mac user sees, so it is recorded in IPAD_PLAN.md for
    /// a decision rather than changed here.
    func color(x: Int, y: Int) -> Color {
        let p = rgba(x: x, y: y)
        if p.a < 8 {
            return .clear
        }
        if p.r > 200, p.g < 80, p.b < 40 {
            return .red
        }
        if p.g > 200, p.r < 80, p.b < 80 {
            return .green
        }
        return .other
    }
}
#endif
