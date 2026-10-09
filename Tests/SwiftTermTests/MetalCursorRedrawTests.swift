#if os(macOS) && canImport(MetalKit)
//
//  MetalCursorRedrawTests.swift
//
//  VGT-10: with the Metal renderer and a steady cursor, output that only
//  moves the cursor must still ask for a frame, or the cursor stays drawn
//  where it was until the next character is typed.
//

import AppKit
import Metal
import Testing

@testable import SwiftTerm

@MainActor
struct MetalCursorRedrawTests {
    /// A terminal view on the Metal renderer showing a typed line, or nil
    /// where this Mac has no Metal device.
    private func metalView() throws -> TerminalView? {
        guard MTLCreateSystemDefaultDevice() != nil else { return nil }
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 400))
        try view.setUseMetal(true)
        view.feed(text: "echo abcdefgh")
        view.updateDisplay(notifyAccessibility: false)
        return view
    }

    @Test("Moving the cursor right with CSI C asks the Metal renderer for a frame")
    func cursorForwardRedraws() throws {
        guard let view = try metalView() else { return }
        view.feed(text: "\u{8}\u{8}\u{8}\u{8}\u{8}")
        view.updateDisplay(notifyAccessibility: false)
        let before = view.metalDisplayRequests

        // zsh's right arrow: no cell changes, only the cursor.
        view.feed(text: "\u{1b}[1C")
        #expect(view.terminal.getUpdateRange() == nil, "nothing on screen changed")
        view.updateDisplay(notifyAccessibility: false)
        #expect(view.metalDisplayRequests == before + 1)
    }

    @Test("Output that leaves the cursor where it was asks for nothing")
    func stillCursorDoesNotRedraw() throws {
        guard let view = try metalView() else { return }
        let before = view.metalDisplayRequests
        view.updateDisplay(notifyAccessibility: false)
        #expect(view.metalDisplayRequests == before)
    }
}
#endif
