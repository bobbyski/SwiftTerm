#if os(macOS)
//
//  WindowAppleMaskTests.swift
//  SwiftTerm — WINDOW_PLAN.md Phase 1, checks 1.7 and 1.8
//
//  The two Mac paths a text mask goes through: the CoreGraphics overlay
//  (layers 1…4 in every mode, and layer 0 under CoreGraphics), and the Metal
//  primitive batches (layers -1 and 0 under Metal).
//

import CoreGraphics
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
@Suite("Window plan: text mask on the Mac renderers")
struct WindowAppleMaskTests {
    private let width = 120
    private let height = 60
    private let hole = VTGLayerClip(x: 20, y: 10, width: 30, height: 20)

    private func command(_ name: String, _ parameters: [String: String]) -> VectorTerminalGraphicsCommand {
        VectorTerminalGraphicsCommand(name: name, parameters: parameters, payload: nil)
    }

    /// A red rectangle over the whole canvas on layer 1, optionally masked.
    private func scene(occluded: Bool) -> VTGGraphicsScene {
        let scene = VTGGraphicsScene()
        if occluded {
            scene.apply(command("layerOcclude", ["layer": "1", "by": "ink"]))
        }
        scene.apply(command("rect", ["id": "r", "layer": "1", "x": "0", "y": "0", "w": "120", "h": "60",
                                     "stroke": "none", "fill": "#ff0000"]))
        return scene
    }

    private func render(_ scene: VTGGraphicsScene, mask: VTGOcclusionMask?) throws -> [UInt8] {
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            vtgPushDrawingContext(context)
            VTGOverlayView(frame: CGRect(x: 0, y: 0, width: width, height: height)).draw(
                scene: scene, plane: nil, in: context,
                bounds: CGRect(x: 0, y: 0, width: width, height: height), textMask: mask)
            vtgPopDrawingContext()
            return true
        }
        try #require(drawn, "could not create a bitmap context")
        return buffer
    }

    private func alpha(_ pixels: [UInt8], x: Int, y: Int) -> UInt8 {
        pixels[(y * width + x) * 4 + 3]
    }

    @Test("CoreGraphics: a masked layer is cut out of the hole and nowhere else")
    func coreGraphicsCutsTheHole() throws {
        let pixels = try render(scene(occluded: true), mask: VTGOcclusionMask(rects: [hole]))
        #expect(alpha(pixels, x: 30, y: 20) == 0, "inside the hole")
        #expect(alpha(pixels, x: 10, y: 20) == 255, "left of the hole")
        #expect(alpha(pixels, x: 30, y: 40) == 255, "below the hole")
    }

    @Test("CoreGraphics rule 1: without layerOcclude a mask changes nothing")
    func coreGraphicsUnchangedWithoutOptIn() throws {
        let masked = try render(scene(occluded: false), mask: VTGOcclusionMask(rects: [hole]))
        let plain = try render(scene(occluded: false), mask: nil)
        #expect(masked == plain)
        #expect(alpha(plain, x: 30, y: 20) == 255)
    }

    private func plan(_ scene: VTGGraphicsScene) -> VTGRenderPlan {
        scene.renderPlan(canvas: VTGRenderCanvas(width: Double(width), height: Double(height)))
    }

    private func area(_ vertices: [ColorVertex]) -> Double {
        var total = 0.0
        var index = 0
        while index + 2 < vertices.count {
            let a = vertices[index].position, b = vertices[index + 1].position, c = vertices[index + 2].position
            total += abs(Double((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))) / 2
            index += 3
        }
        return total
    }

    @Test("Metal: masked triangles keep exactly the area outside the hole")
    func metalClipsTriangles() {
        let batches = VTGMetalPrimitiveRenderer.makeBatches(
            plan: plan(scene(occluded: true)), scale: 1, drawableHeight: CGFloat(height),
            textMask: VTGOcclusionMask(rects: [hole]))
        let vertices = batches.flatMap(\.vertices)
        #expect(abs(area(vertices) - Double(width * height - 30 * 20)) < 0.5)
        // No vertex lies strictly inside the hole (vertex space is y-up).
        let holeMinY = Float(height) - Float(hole.y + hole.height)
        let holeMaxY = Float(height) - Float(hole.y)
        #expect(!vertices.contains { v in
            v.position.x > Float(hole.x) + 0.01 && v.position.x < Float(hole.x + hole.width) - 0.01
                && v.position.y > holeMinY + 0.01 && v.position.y < holeMaxY - 0.01
        })
    }

    @Test("Metal rule 1: without layerOcclude the batches are byte-for-byte the old ones")
    func metalUnchangedWithoutOptIn() {
        let unmaskedPlan = plan(scene(occluded: false))
        let withMask = VTGMetalPrimitiveRenderer.makeBatches(
            plan: unmaskedPlan, scale: 2, drawableHeight: 120, textMask: VTGOcclusionMask(rects: [hole]))
        let without = VTGMetalPrimitiveRenderer.makeBatches(plan: unmaskedPlan, scale: 2, drawableHeight: 120)
        #expect(withMask.map(\.vertices.count) == without.map(\.vertices.count))
        #expect(zip(withMask.flatMap(\.vertices), without.flatMap(\.vertices)).allSatisfy {
            $0.position == $1.position && $0.color == $1.color
        })
    }
}
#endif
