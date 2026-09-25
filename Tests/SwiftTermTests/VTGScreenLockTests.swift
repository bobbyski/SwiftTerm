import Foundation
import Testing

@testable import SwiftTerm

/// `screenLock` — an exact resolution and text grid, for a program copying a
/// particular machine (VTG 1.6.0).
@Suite("VTG screen lock")
struct VTGScreenLockTests {
    private func command(_ name: String, _ parameters: [String: String] = [:]) -> VectorTerminalGraphicsCommand {
        VectorTerminalGraphicsCommand(name: name, parameters: parameters)
    }

    private func field(_ response: String, _ key: String) -> String? {
        response.split(separator: ",").first { $0.hasPrefix("\(key)=") }
            .map { String($0.dropFirst(key.count + 1)) }
            .map { $0.hasSuffix("\u{1b}\\") ? String($0.dropLast(2)) : $0 }
    }

    // MARK: - The layout

    @Test("The screen is scaled by a whole number and centred, the rest is border")
    func wholeMultipleAndCentred() throws {
        let lock = try #require(VTGScreenLock(width: 320, height: 200, columns: 40, rows: 25))
        let layout = try #require(lock.layout(inWidth: 1000, frameHeight: 700))
        // 1000/320 is 3.1 and 700/200 is 3.5: three fits, four does not.
        #expect(layout.scale == 3)
        #expect(layout.width == 960)
        #expect(layout.height == 600)
        #expect(layout.x == 20)      // (1000 - 960) / 2
        #expect(layout.y == 50)      // (700 - 600) / 2
        #expect(layout.isExact)
    }

    @Test("An exact fit is ×1 with no border")
    func exactFit() throws {
        let lock = try #require(VTGScreenLock(width: 320, height: 200, columns: 40, rows: 25))
        let layout = try #require(lock.layout(inWidth: 320, frameHeight: 200))
        #expect(layout.scale == 1)
        #expect(layout.x == 0 && layout.y == 0)
        #expect(layout.isExact)
    }

    @Test("A frame too small for ×1 is fitted, and says it is not exact")
    func tooSmallToBeExact() throws {
        let lock = try #require(VTGScreenLock(width: 320, height: 200, columns: 40, rows: 25))
        let layout = try #require(lock.layout(inWidth: 160, frameHeight: 200))
        #expect(layout.scale == 0.5)
        #expect(layout.width == 160 && layout.height == 100)
        #expect(!layout.isExact)
    }

    @Test("A cell is the screen divided by the grid, at ×1 and scaled")
    func cellSize() throws {
        let lock = try #require(VTGScreenLock(width: 320, height: 200, columns: 40, rows: 25))
        #expect(lock.cellSize == (width: 8, height: 8))
        let layout = try #require(lock.layout(inWidth: 1000, frameHeight: 700))
        #expect(layout.cellSize(for: lock) == (width: 24, height: 24))
    }

    @Test("A screen needs a size and a grid")
    func rejectsNonsense() {
        #expect(VTGScreenLock(width: 0, height: 200, columns: 40, rows: 25) == nil)
        #expect(VTGScreenLock(width: 320, height: 200, columns: 0, rows: 25) == nil)
    }

    // MARK: - The protocol

    @Test("Locking changes the canvas every query reports, without the window moving")
    func lockedCanvasIsWhatProgramsSee() {
        let controller = VTGHostController()
        let window = VTGCanvasSize(width: 1000, height: 700)

        let locked = controller.process(
            [command("screenLock", ["width": "320", "height": "200", "cols": "40", "rows": "25"])],
            canvas: window
        )
        #expect(locked.first?.contains("_VTG;screen") == true)
        #expect(field(locked[0], "width") == "320")
        #expect(field(locked[0], "scale") == "3")
        #expect(field(locked[0], "exact") == "1")

        let canvas = controller.process([command("canvas?")], canvas: window)
        #expect(field(canvas[0], "width") == "320")
        #expect(field(canvas[0], "height") == "200")

        let capabilities = controller.process([command("capabilities?")], canvas: window)
        #expect(capabilities[0].contains("canvasWidth=320"))
        #expect(capabilities[0].contains("screenLock"))

        // The cell is the locked grid's, not whatever the view's font measures.
        let glyph = controller.process([command("glyphSize?")], canvas: window, glyphSize: (width: 7, height: 15))
        #expect(field(glyph[0], "width") == "8")
        #expect(field(glyph[0], "height") == "8")
    }

    @Test("Unlocking gives the window back")
    func unlockRestoresTheWindow() {
        let controller = VTGHostController()
        let window = VTGCanvasSize(width: 1000, height: 700)
        _ = controller.process(
            [command("screenLock", ["width": "320", "height": "200", "cols": "40", "rows": "25"])],
            canvas: window
        )
        let unlocked = controller.process([command("screenUnlock")], canvas: window)
        #expect(field(unlocked[0], "locked") == "0")
        #expect(controller.screenLock == nil)

        let canvas = controller.process([command("size?")], canvas: window)
        #expect(field(canvas[0], "width") == "1000")
    }

    @Test("A subscriber is told the canvas changed, because for it it did")
    func lockSendsAResizeEvent() {
        let controller = VTGHostController()
        let window = VTGCanvasSize(width: 1000, height: 700)
        _ = controller.process([command("resizeEvents", ["enabled": "1"])], canvas: window)

        let locked = controller.process(
            [command("screenLock", ["width": "320", "height": "200", "cols": "40", "rows": "25"])],
            canvas: window
        )
        #expect(locked.contains { $0.contains("_VTG;resize") && $0.contains("width=320") })

        let unlocked = controller.process([command("screenUnlock")], canvas: window)
        #expect(unlocked.contains { $0.contains("_VTG;resize") && $0.contains("width=1000") })
    }

    @Test("A resolution with no grid gets the 8×8 cells the machines had")
    func gridDefaultsToEightByEight() {
        let controller = VTGHostController()
        _ = controller.process(
            [command("screenLock", ["width": "320", "height": "200"])],
            canvas: VTGCanvasSize(width: 1000, height: 700)
        )
        #expect(controller.screenLock?.columns == 40)
        #expect(controller.screenLock?.rows == 25)
    }

    @Test("screen? answers when nothing is locked, which is the default")
    func unlockedIsTheDefault() {
        let controller = VTGHostController()
        let response = controller.process([command("screen?")], canvas: VTGCanvasSize(width: 800, height: 600))
        #expect(field(response[0], "locked") == "0")
        #expect(controller.screenLock == nil)
    }

    @Test("A new guest gets an unlocked screen")
    func resetUnlocks() {
        let controller = VTGHostController()
        _ = controller.process(
            [command("screenLock", ["width": "256", "height": "192", "cols": "32", "rows": "24"])],
            canvas: VTGCanvasSize(width: 1000, height: 700)
        )
        controller.resetSession()
        #expect(controller.screenLock == nil)
    }

    @Test("A page opens inside the locked screen, not inside the window")
    func pagesUseTheLockedScreen() {
        let controller = VTGHostController()
        let window = VTGCanvasSize(width: 1000, height: 700)
        _ = controller.process(
            [command("screenLock", ["width": "320", "height": "200", "cols": "40", "rows": "25"])],
            canvas: window
        )
        let response = controller.process([command("windowCanvas?")], canvas: window)
        #expect(field(response[0], "width") == "320")
        #expect(field(response[0], "height") == "200")
    }
}
