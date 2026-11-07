//
//  WindowTextMaskTests.swift
//  SwiftTerm — WINDOW_PLAN.md Phase 1 (cell mask, ink rule); twin of the SwiftTermGL suites
//

import Foundation
import Testing
@testable import SwiftTerm

struct WindowInkRuleTests {
    private func firstCell(after text: String) -> CharData {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 2)
        terminal.feed(text: text)
        return terminal.getLine(row: 0)![0]
    }

    @Test("Blank default cells have no ink; text, color and decorations do")
    func inkRule() {
        let esc = "\u{1b}"
        #expect(!VTGCellInkRule.hasInk(firstCell(after: "")))
        #expect(!VTGCellInkRule.hasInk(firstCell(after: " ")))
        #expect(VTGCellInkRule.hasInk(firstCell(after: "A")))
        #expect(VTGCellInkRule.hasInk(firstCell(after: "\(esc)[44m ")))
        #expect(VTGCellInkRule.hasInk(firstCell(after: "\(esc)[48;2;1;2;3m ")))
        #expect(VTGCellInkRule.hasInk(firstCell(after: "\(esc)[7m ")))
        #expect(VTGCellInkRule.hasInk(firstCell(after: "\(esc)[4m ")))
        #expect(VTGCellInkRule.hasInk(firstCell(after: "\(esc)[9m ")))
        #expect(!VTGCellInkRule.hasInk(firstCell(after: "\(esc)[8mA")), "invisible text shows nothing")
        #expect(VTGCellInkRule.hasInk(firstCell(after: "\u{2502}")), "box drawing is ink")
    }

    @Test("Runs merge across a row, and a wide character covers both its columns")
    func runs() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 12, rows: 2)
        terminal.feed(text: "ab  c\u{4E2D}  d")
        // a b _ _ c 中中 _ _ d
        let runs = VTGTextOcclusionMaskBuilder.inkRuns(in: terminal.getLine(row: 0)!, columns: 12)
        #expect(runs == [0..<2, 4..<7, 9..<10])
    }
}

struct WindowMaskBuilderTests {
    @Test("The fixture's mask holds the border, the colored interior, and nothing else")
    func fixtureMask() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: WindowFixture.cols, rows: WindowFixture.rows)
        WindowFixture.drawTextWindow(into: terminal)
        let mask = VTGTextOcclusionMaskBuilder().mask(for: terminal, cellWidth: 10, cellHeight: 20)
        let left = Double(WindowFixture.windowLeft) * 10
        let width = Double(WindowFixture.windowRight - WindowFixture.windowLeft + 1) * 10
        #expect(mask.rects.contains(VTGLayerClip(x: left, y: 20, width: width, height: 20)), "top border")
        #expect(mask.rects.contains(VTGLayerClip(x: left, y: 40, width: width, height: 20)), "colored interior row")
        // The default interior row has ink only at its two borders.
        let row3 = mask.rects.filter { $0.y == 60 }
        #expect(row3 == [VTGLayerClip(x: left, y: 60, width: 10, height: 20),
                         VTGLayerClip(x: Double(WindowFixture.windowRight) * 10, y: 60, width: 10, height: 20)])
        #expect(mask.rects.allSatisfy { $0.y < 100 }, "nothing below the window")
    }

    @Test("Unchanged rows are not rescanned")
    func rowCache() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 5)
        terminal.feed(text: "hello\r\nworld")
        let builder = VTGTextOcclusionMaskBuilder()
        _ = builder.mask(for: terminal, cellWidth: 8, cellHeight: 16)
        #expect(builder.lastRescannedRowCount == 5)
        _ = builder.mask(for: terminal, cellWidth: 8, cellHeight: 16)
        #expect(builder.lastRescannedRowCount == 0)
        terminal.feed(text: "!")
        _ = builder.mask(for: terminal, cellWidth: 8, cellHeight: 16)
        #expect(builder.lastRescannedRowCount == 1)
    }
}

struct WindowLayerOccludeCommandTests {
    private let canvas = VTGCanvasSize(width: 200, height: 100)

    private func command(_ name: String, _ parameters: [String: String]) -> VectorTerminalGraphicsCommand {
        VectorTerminalGraphicsCommand(name: name, parameters: parameters)
    }

    @Test("Every layer starts unmasked, and plans say so")
    func defaultIsNone() {
        let scene = VTGGraphicsScene()
        scene.apply(command("rect", ["id": "r", "x": "0", "y": "0", "w": "10", "h": "10", "layer": "0"]))
        #expect(scene.occlusion(for: 0) == .none)
        #expect(!scene.usesTextOcclusion)
        #expect(scene.renderPlan(canvas: canvas).entries.allSatisfy { $0.occlusion == .none })
    }

    @Test("layerOcclude sets, clears, and is reset by clear")
    func setAndClear() {
        let scene = VTGGraphicsScene()
        #expect(scene.apply(command("layerOcclude", ["layer": "2", "by": "ink"])))
        scene.apply(command("rect", ["id": "r", "x": "0", "y": "0", "w": "10", "h": "10", "layer": "2"]))
        scene.apply(command("rect", ["id": "s", "x": "0", "y": "0", "w": "10", "h": "10", "layer": "1"]))
        #expect(scene.occlusion(for: 2) == .ink)
        let plan = scene.renderPlan(canvas: canvas)
        #expect(plan.entries.first { $0.primitive.id == "r" }?.occlusion == .ink)
        #expect(plan.entries.first { $0.primitive.id == "s" }?.occlusion == VTGLayerOcclusion.none)

        scene.apply(command("layerOcclude", ["layer": "2", "by": "none"]))
        #expect(scene.occlusion(for: 2) == .none)
        scene.apply(command("layerOcclude", ["layer": "2", "by": "ink"]))
        scene.apply(command("clear", [:]))
        #expect(scene.occlusion(for: 2) == .none)
    }

    @Test("An unknown by= value hides nothing")
    func typoIsNone() {
        let scene = VTGGraphicsScene()
        scene.apply(command("layerOcclude", ["layer": "1", "by": "inc"]))
        #expect(scene.occlusion(for: 1) == .none)
    }

    @Test("Snapshots carry occlusion, so offscreen frames keep it")
    func snapshot() {
        let scene = VTGGraphicsScene()
        scene.apply(command("layerOcclude", ["layer": "0", "by": "ink"]))
        #expect(scene.makeSnapshot().occlusion(for: 0) == .ink)
    }

    @Test("Capabilities advertise occlusion=ink in a new field at the end")
    func capability() {
        let response = VTGResponseEncoder.capabilities(canvas: canvas)
        #expect(response.contains(",occlusion=ink\u{1b}\\"))
        #expect(response.contains("textPlane=reserved"), "existing tokens are unchanged")
        #expect(!response.contains("layerOcclude"), "the shared commands list keeps its exact shape")
    }
}

