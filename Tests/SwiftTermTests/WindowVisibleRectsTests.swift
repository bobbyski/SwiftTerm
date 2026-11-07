//
//  WindowVisibleRectsTests.swift
//  WINDOW_PLAN.md Phase 1 — the visible part of a canvas under a text mask.
//  Identical in SwiftTerm and SwiftTermGL.
//

import Foundation
import Testing
@testable import SwiftTerm

struct WindowVisibleRectsTests {
    private func area(_ rects: [VTGLayerClip]) -> Double {
        rects.reduce(0) { $0 + $1.width * $1.height }
    }

    private func overlaps(_ a: VTGLayerClip, _ b: VTGLayerClip) -> Bool {
        a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
    }

    @Test("No holes leaves the whole canvas")
    func noHoles() {
        #expect(VTGOcclusionMask.empty.visibleRects(width: 100, height: 50)
            == [VTGLayerClip(x: 0, y: 0, width: 100, height: 50)])
    }

    @Test("One hole leaves the canvas minus the hole, in disjoint rectangles")
    func oneHole() {
        let mask = VTGOcclusionMask(rects: [VTGLayerClip(x: 20, y: 10, width: 30, height: 10)])
        let visible = mask.visibleRects(width: 100, height: 50)
        #expect(area(visible) == 100 * 50 - 30 * 10)
        #expect(visible.allSatisfy { !overlaps($0, mask.rects[0]) })
        for (i, a) in visible.enumerated() {
            for b in visible[(i + 1)...] {
                #expect(!overlaps(a, b))
            }
        }
    }

    @Test("Rows with the same gaps merge into one rectangle per gap")
    func bandsMerge() {
        // A two-row-tall window border on the left of rows 1 and 2.
        let mask = VTGOcclusionMask(rects: [
            VTGLayerClip(x: 0, y: 10, width: 10, height: 10),
            VTGLayerClip(x: 0, y: 20, width: 10, height: 10),
        ])
        let visible = mask.visibleRects(width: 100, height: 40)
        #expect(area(visible) == 100 * 40 - 200)
        #expect(visible.contains(VTGLayerClip(x: 10, y: 10, width: 90, height: 20)), "rows 1 and 2 merged")
    }
}
