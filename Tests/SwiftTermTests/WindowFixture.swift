//
//  WindowFixture.swift
//  SwiftTerm — WINDOW_PLAN.md Phase 0 (twin of the SwiftTermGL fixture)
//
//  One scene, reused by every window-plan test: VTG graphics on layers -1, 0
//  and 1, and a text window drawn over them with box-drawing characters.
//
//      cols 0         4                     16
//      row 0  ┌──────────────── layer 0 bar (blue) ───────────────┐
//      row 1  │ layer -1 (green)     ┌─────────────┐   ●●●●●●●     │
//      row 2  │                      │█████████████│ ●●●●●●●●●●    │  ← colored interior
//      row 3  │                      │             │ ●●●●●●●●●●    │  ← default interior
//      row 4  │                      └─────────────┘   ●●●●●●       │
//
//  The window is plain terminal text — exactly what `dialog` or a PRINT box
//  draws — so it shows how VTG graphics and text windows stack today.
//  Box-drawing characters render procedurally, not from the font, which keeps
//  golden images stable across FreeType versions.
//

import Foundation
@testable import SwiftTerm

enum WindowFixture {
    static let cols = 18
    static let rows = 7

    /// The window's frame, in cells: columns 4…13, rows 1…4.
    static let windowLeft = 4
    static let windowRight = 13
    static let windowTop = 1
    static let windowBottom = 4

    /// Feed the text window into a terminal.
    static func drawTextWindow(into terminal: Terminal) {
        let esc = "\u{1b}"
        let inner = windowRight - windowLeft - 1
        let horizontal = String(repeating: "\u{2500}", count: inner)
        func at(_ row: Int, _ col: Int) -> String { "\(esc)[\(row + 1);\(col + 1)H" }
        terminal.feed(text: "\(esc)[38;2;230;230;230m")
        terminal.feed(text: at(windowTop, windowLeft) + "\u{250C}" + horizontal + "\u{2510}")
        // A colored interior: the background itself is ink.
        terminal.feed(text: at(windowTop + 1, windowLeft) + "\u{2502}"
            + "\(esc)[48;2;40;60;160m" + String(repeating: " ", count: inner) + "\(esc)[49m" + "\u{2502}")
        // A default-background interior: spaces with no ink at all.
        terminal.feed(text: at(windowTop + 2, windowLeft) + "\u{2502}"
            + String(repeating: " ", count: inner) + "\u{2502}")
        terminal.feed(text: at(windowBottom, windowLeft) + "\u{2514}" + horizontal + "\u{2518}")
        terminal.feed(text: "\(esc)[0m")
    }

    /// The VTG commands that draw the graphics under the window.
    static func graphicsCommands(cellWidth: Double, cellHeight: Double) -> [VectorTerminalGraphicsCommand] {
        let width = Double(cols) * cellWidth
        let height = Double(rows) * cellHeight
        func number(_ value: Double) -> String { String(value) }
        return [
            // Layer -1: a green block behind the left half, window included.
            VectorTerminalGraphicsCommand(name: "rect", parameters: [
                "id": "under", "x": "0", "y": number(cellHeight),
                "w": number(width * 0.5), "h": number(cellHeight * 4),
                "fill": "#22c55e", "layer": "-1",
            ]),
            // Layer 0: a blue bar along the top row, reaching past the middle of
            // row 1 so it crosses the window's top border line.
            VectorTerminalGraphicsCommand(name: "rect", parameters: [
                "id": "bar", "x": "0", "y": "0",
                "w": number(width), "h": number(cellHeight * 1.75),
                "fill": "#3b82f6", "layer": "0",
            ]),
            // Layer 1: a red disc over the right half of the window.
            VectorTerminalGraphicsCommand(name: "circle", parameters: [
                "id": "disc", "cx": number(width * 0.62), "cy": number(height * 0.45),
                "r": number(cellHeight * 2), "fill": "#ef4444", "layer": "1",
            ]),
        ]
    }

    /// The center of a cell, in canvas points.
    static func center(col: Int, row: Int, cellWidth: Double, cellHeight: Double) -> (x: Double, y: Double) {
        ((Double(col) + 0.5) * cellWidth, (Double(row) + 0.5) * cellHeight)
    }
}
