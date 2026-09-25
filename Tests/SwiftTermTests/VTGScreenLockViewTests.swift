#if os(macOS) || os(iOS)
import CoreGraphics
import Foundation
import Testing

@testable import SwiftTerm

/// A locked screen in a real view: the grid it asked for, the cell that grid
/// implies, and pixels scaled by a whole number (IPAD_PLAN-era VTG 1.6.0).
///
/// The same expectations on AppKit and UIKit — a locked screen is a claim about
/// what the program sees, and it has to hold on both.
@MainActor
@Suite("VTG screen lock in the view")
struct VTGScreenLockViewTests {
    /// A 320×200 screen with a 40×25 grid: a Commodore-shaped screen, and the
    /// example in the documentation.
    private func lockBytes(width: Int = 320, height: Int = 200, columns: Int = 40, rows: Int = 25) -> [UInt8] {
        Array("\u{1b}_VTG;screenLock,width=\(width),height=\(height),cols=\(columns),rows=\(rows)\u{1b}\\".utf8)
    }

    private func unlockBytes() -> [UInt8] {
        Array("\u{1b}_VTG;screenUnlock\u{1b}\\".utf8)
    }

    @Test("Locking sets the grid and the cell the screen implies")
    func gridAndCell() {
        let view = VectorTerminalView(frame: CGRect(x: 0, y: 0, width: 960, height: 600))
        view.feed(byteArray: lockBytes()[...])

        #expect(view.vtgScreenLock?.width == 320)
        #expect(view.getTerminal().cols == 40)
        #expect(view.getTerminal().rows == 25)
        // 960 wide over 40 columns, 600 over 25 rows: ×3 of an 8×8 cell.
        let cell = view.currentVTGCellSize()
        #expect(cell?.width == 24)
        #expect(cell?.height == 24)
    }

    @Test("Unlocking gives back a terminal whose font decides its cell")
    func unlockRestoresTheFont() {
        let view = VectorTerminalView(frame: CGRect(x: 0, y: 0, width: 960, height: 600))
        let cellBefore = view.currentVTGCellSize()
        view.feed(byteArray: lockBytes()[...])
        #expect(view.currentVTGCellSize()?.width == 24)

        view.feed(byteArray: unlockBytes()[...])
        #expect(view.vtgScreenLock == nil)
        #expect(view.currentVTGCellSize()?.width == cellBefore?.width)
    }

    @Test("The screen is centred in its container at a whole multiple")
    func containerCentresTheScreen() {
        let view = VectorTerminalView(frame: .zero)
        let container = VTGTerminalOverlayContainerView(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
            terminalContentView: view
        )
        view.feed(byteArray: lockBytes()[...])
        container.vtgLayoutIfNeeded()
        #if os(macOS)
        container.layout()
        #else
        container.layoutSubviews()
        #endif

        // ×3 of 320×200 is 960×600, with the 40 and 100 left over as border.
        #expect(view.frame == CGRect(x: 20, y: 50, width: 960, height: 600))
        #expect(container.overlayView.frame == view.frame)
    }

    @Test("An unlocked terminal still fills its container")
    func containerFillsWhenUnlocked() {
        let view = VectorTerminalView(frame: .zero)
        let container = VTGTerminalOverlayContainerView(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
            terminalContentView: view
        )
        container.vtgLayoutIfNeeded()
        #if os(macOS)
        container.layout()
        #else
        container.layoutSubviews()
        #endif
        #expect(view.frame == CGRect(x: 0, y: 0, width: 1000, height: 700))
    }

    @Test("One locked pixel becomes a whole block, in the right place")
    func onePixelIsABlock() throws {
        // A 32×20 screen in a 96×60 view: ×3, so VTG pixel (1,1) is the block
        // from (3,3) to (5,5) and nothing outside it.
        let scene = VTGGraphicsScene()
        scene.apply(VectorTerminalGraphicsCommand(
            name: "rect",
            parameters: ["id": "p", "layer": "1", "x": "1", "y": "1", "w": "1", "h": "1",
                         "stroke": "none", "fill": "#ff0000"],
            payload: nil
        ))
        let pixels = try render(scene: scene, lockedTo: VTGCanvasSize(width: 32, height: 20), inView: CGSize(width: 96, height: 60))

        #expect(pixels.isRed(x: 3, y: 3))
        #expect(pixels.isRed(x: 5, y: 5))
        #expect(!pixels.isRed(x: 2, y: 3))      // one device pixel left of the block
        #expect(!pixels.isRed(x: 6, y: 5))      // and one right of it
        #expect(!pixels.isRed(x: 3, y: 6))      // and one below
    }

    @Test("A screen fills its view edge to edge when scaled")
    func screenFillsTheView() throws {
        let scene = VTGGraphicsScene()
        scene.apply(VectorTerminalGraphicsCommand(
            name: "rect",
            parameters: ["id": "all", "layer": "1", "x": "0", "y": "0", "w": "32", "h": "20",
                         "stroke": "none", "fill": "#ff0000"],
            payload: nil
        ))
        let pixels = try render(scene: scene, lockedTo: VTGCanvasSize(width: 32, height: 20), inView: CGSize(width: 96, height: 60))
        #expect(pixels.isRed(x: 0, y: 0))
        #expect(pixels.isRed(x: 95, y: 59))
    }

    // MARK: - Rendering

    private func render(scene: VTGGraphicsScene, lockedTo locked: VTGCanvasSize, inView size: CGSize) throws -> Pixels {
        let width = Int(size.width), height = Int(size.height)
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let overlay = VTGOverlayView(frame: CGRect(origin: .zero, size: size))
        overlay.lockedCanvas = locked
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
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            vtgPushDrawingContext(context)
            overlay.drawLocked(in: context, bounds: CGRect(origin: .zero, size: size)) { canvasBounds in
                overlay.draw(scene: scene, plane: nil, in: context, bounds: canvasBounds)
            }
            vtgPopDrawingContext()
            return true
        }
        try #require(drawn, "could not create a bitmap context")
        return Pixels(bytes: buffer, width: width)
    }
}

private struct Pixels {
    let bytes: [UInt8]
    let width: Int

    func isRed(x: Int, y: Int) -> Bool {
        let index = (y * width + x) * 4
        return bytes[index] > 200 && bytes[index + 1] < 60 && bytes[index + 2] < 60
    }
}
#endif
