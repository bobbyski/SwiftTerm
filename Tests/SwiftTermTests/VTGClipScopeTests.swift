//
//  VTGClipScopeTests.swift
//
//  Whether `clip` can be scoped to a single draw decides whether VTG needs a
//  source rectangle on `image`. A consumer drawing a partially scrolled image
//  wants it *cropped*; today the destination rect is clipped and the whole
//  image is scaled into it, so it is squashed instead.
//
//  The hoped-for cheap answer was `clip` → `image` → `clipClear` around one
//  primitive, which would need no protocol change. These tests record why that
//  does not work, so the question is settled rather than re-asked.
//

import Foundation
import Testing

@testable import SwiftTerm

@Suite("VTG clip scope")
struct VTGClipScopeTests {

    private func command(_ name: String, _ parameters: [String: String] = [:]) -> VectorTerminalGraphicsCommand {
        VectorTerminalGraphicsCommand(name: name, parameters: parameters)
    }

    /// A clip belongs to a layer, not to the primitive that follows it.
    @Test("Clip state is layer-wide, not per-primitive")
    func clipIsLayerWide() {
        let scene = VTGGraphicsScene()
        scene.apply(command("clip", ["layer": "1", "x": "10", "y": "10", "w": "50", "h": "50"]))

        let clip = scene.layerClips[1]
        #expect(clip != nil, "clip is recorded against the layer")
        #expect(clip?.width == 50)
        // Nothing ties it to a primitive: it is one entry keyed by layer.
        #expect(scene.layerClips.count == 1)
    }

    /// The scene is retained and rendered after every command in the frame has
    /// been applied, so clearing the clip in the same frame leaves nothing
    /// clipped — the enclosing pair cannot scope a single draw.
    @Test("Clip and clipClear in one frame leave no clip at all")
    func clipAroundOneDrawDoesNotScope() {
        let scene = VTGGraphicsScene()

        scene.apply(command("clip", ["layer": "1", "x": "0", "y": "0", "w": "40", "h": "40"]))
        scene.apply(command("rect", ["id": "r", "layer": "1", "x": "0", "y": "0", "w": "100", "h": "100"]))
        scene.apply(command("clipClear", ["layer": "1"]))

        #expect(scene.layerClips[1] == nil,
                "the clip is gone before anything is drawn, so it scopes nothing")
    }

    /// Clipping a layer to crop one image would crop everything else on it too,
    /// which is the same objection that rules out `scrollLayer` for page
    /// content: the layer carries other consumers' drawing.
    @Test("A layer clip applies to every primitive on that layer")
    func clipAffectsEveryPrimitiveOnTheLayer() {
        let scene = VTGGraphicsScene()
        scene.apply(command("rect", ["id": "a", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("rect", ["id": "b", "layer": "1", "x": "50", "y": "50", "w": "10", "h": "10"]))
        scene.apply(command("clip", ["layer": "1", "x": "0", "y": "0", "w": "20", "h": "20"]))

        // One clip, two primitives: there is no per-primitive clip to set.
        #expect(scene.layerClips[1] != nil)
        #expect(scene.layerClips.count == 1)
    }
}
