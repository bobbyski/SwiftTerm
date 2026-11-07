//
//  WindowRasterTextTests.swift
//  WINDOW_PLAN.md Phase 5 — raster mode where text erases drawing.
//  Identical in SwiftTerm and SwiftTermGL.
//

import Foundation
import Testing
@testable import SwiftTerm

/// Records what the terminal reports.
private final class Recorder: TerminalCellWriteObserver {
    var events: [String] = []
    func cellsWritten(row: Int, columns: Range<Int>) { events.append("w\(row):\(columns.lowerBound)-\(columns.upperBound)") }
    func rowsScrolled(top: Int, bottom: Int, count: Int) { events.append("s\(top)-\(bottom):\(count)") }
    func screenInvalidated() { events.append("x") }
}

struct WindowWriteHookTests {
    private let esc = "\u{1b}"

    private func recorded(_ text: String, cols: Int = 10, rows: Int = 4, setup: String = "") -> [String] {
        let terminal = TerminalTestHarness.makeTerminal(cols: cols, rows: rows).terminal
        terminal.feed(text: setup)
        let recorder = Recorder()
        terminal.cellWriteObserver = recorder
        terminal.feed(text: text)
        return recorder.events
    }

    @Test("5.3: printing reports every cell written, a space over a space included")
    func prints() {
        #expect(recorded("abc") == ["w0:0-3"])
        #expect(recorded("   ") == ["w0:0-3"], "spaces over blank cells count")
        #expect(recorded("\(esc)[2;4Hé") == ["w1:3-4"])
        #expect(recorded("\u{4E2D}") == ["w0:0-2"], "a wide character covers both its cells")
    }

    @Test("5.3: erases report their cells")
    func erases() {
        #expect(recorded("\(esc)[1;3H\(esc)[K") == ["w0:2-10"], "EL to end")
        #expect(recorded("\(esc)[1;3H\(esc)[1K") == ["w0:0-3"], "EL to start")
        #expect(recorded("\(esc)[1;3H\(esc)[2X") == ["w0:2-4"], "ECH")
        #expect(recorded("\(esc)[2J") == ["w3:0-10", "w2:0-10", "w1:0-10", "w0:0-10"], "ED all")
        #expect(recorded("\(esc)[1;3H\(esc)[2@") == ["w0:2-10"], "ICH shifts to the margin")
        #expect(recorded("\(esc)[1;3H\(esc)[2P") == ["w0:2-10"], "DCH shifts to the margin")
    }

    @Test("5.3: scrolling reports the region and the distance")
    func scrolls() {
        #expect(recorded("\(esc)[4;1H\n") == ["s0-3:1"], "line feed at the bottom")
        #expect(recorded("\(esc)[1;1H\(esc)M") == ["s0-3:-1"], "reverse index at the top")
        #expect(recorded("\(esc)[2;1H\(esc)[1L") == ["s1-3:-1"], "IL")
        #expect(recorded("\(esc)[2;1H\(esc)[2M") == ["s1-3:2"], "DL")
        #expect(recorded("\(esc)[2S") == ["s0-3:2"], "SU")
        #expect(recorded("\(esc)[1T") == ["s0-3:-1"], "SD")
        #expect(recorded("\(esc)[2;3r\(esc)[3;1H\n") == ["s1-2:1"], "inside a scroll region")
    }

    @Test("5.3: resets, alignment and the alternate screen invalidate everything")
    func invalidations() {
        #expect(recorded("\(esc)c").contains("x"))
        #expect(recorded("\(esc)#8").last == "x")
        #expect(recorded("\(esc)[?1049h").contains("x"))
    }

    @Test("5.3: nothing is reported without an observer")
    func silentByDefault() {
        let terminal = TerminalTestHarness.makeTerminal(cols: 10, rows: 4).terminal
        terminal.feed(text: "abc\(esc)[2J")
        #expect(terminal.cellWriteObserver == nil)
    }
}

struct WindowRasterCanvasTests {
    private let canvasSize = VTGCanvasSize(width: 640, height: 480)
    private func command(_ name: String, _ parameters: [String: String]) -> VectorTerminalGraphicsCommand {
        VectorTerminalGraphicsCommand(name: name, parameters: parameters)
    }

    @Test("Runs on one row join; a clear drops what was queued")
    func queue() {
        let canvas = VTGRasterCanvas()
        canvas.cellsWritten(row: 1, columns: 0..<3)
        canvas.cellsWritten(row: 1, columns: 3..<5)
        canvas.cellsWritten(row: 2, columns: 0..<1)
        #expect(canvas.operations == [.eraseCells(row: 1, columns: 0..<5), .eraseCells(row: 2, columns: 0..<1)])
        canvas.screenInvalidated()
        #expect(canvas.operations == [.clear])
        #expect(canvas.takeOperations() == [.clear])
        #expect(canvas.operations.isEmpty)
    }

    @Test("5.2: with text=erases, 10,000 pixels retain nothing (Finding B fixed for programs that ask)")
    func nothingRetained() {
        let controller = VTGHostController()
        var attached: [Bool] = []
        controller.rasterTextModeDidChange = { attached.append($0 != nil) }
        controller.process([command("rasterMode", ["enabled": "1", "text": "erases"])], canvas: canvasSize)
        #expect(controller.isRasterMode && controller.isRasterTextErasing)
        _ = controller.rasterCanvas.takeOperations()
        controller.process((0..<10_000).map { command("pixel", ["id": "dot", "x": String($0 % 640), "y": String($0 / 640)]) },
                           canvas: canvasSize)
        #expect(controller.scene.primitives.isEmpty)
        #expect(controller.rasterCanvas.operations.count == 10_000)
        controller.process([command("rasterMode", ["enabled": "0"])], canvas: canvasSize)
        #expect(attached == [true, false])
        #expect(!controller.isRasterTextErasing)
    }

    @Test("Rule 3: plain raster mode is exactly what it was")
    func plainUnchanged() {
        let controller = VTGHostController()
        var called = false
        controller.rasterTextModeDidChange = { _ in called = true }
        controller.process([command("rasterMode", ["enabled": "1"]),
                            command("pixel", ["id": "dot", "x": "1", "y": "1"])], canvas: canvasSize)
        #expect(controller.scene.primitives.count == 1)
        #expect(controller.rasterCanvas.operations.isEmpty)
        #expect(!called)
    }

    @Test("A clear in text=erases mode clears the framebuffer and keeps sprite assets")
    func clearCommand() {
        let controller = VTGHostController()
        controller.process([command("rasterMode", ["enabled": "1", "text": "erases"]),
                            command("rect", ["id": "r", "x": "0", "y": "0", "w": "4", "h": "4"]),
                            command("clear", [:])], canvas: canvasSize)
        #expect(controller.rasterCanvas.operations == [.clear])
    }

    @Test("rasterText=erases is advertised only by a host that draws the canvas")
    func advertisement() {
        let controller = VTGHostController()
        let plain = controller.process([command("capabilities?", [:])], canvas: canvasSize)
        #expect(plain.first?.contains("rasterText") == false)
        controller.advertisesRasterText = true
        let drawn = controller.process([command("capabilities?", [:])], canvas: canvasSize)
        #expect(drawn.first?.contains(",rasterText=erases,rasterQueueMax=200000") == true)
    }
}
