//
//  VTGMetalEllipseFanTests.swift
//
//  A filled circle is drawn as a triangle fan whose apex is the centre, so the
//  rim must wrap: the wedge between the last rim point and the first is a real
//  wedge like any other. `appendTriangleFan` emits (apex, i, i+1) and stops at
//  the final pair — correct for a fan whose apex is a vertex of the shape,
//  wrong for one whose apex is the centre.
//
//  Left unclosed, every filled circle in the Metal renderer was missing a 7.5°
//  slice at mid-height on the right. It reads as a thin radial line wherever
//  something else is painted underneath — a donut hole over a pie chart, most
//  visibly.
//
//  These tests measure the angular coverage of the emitted triangles rather
//  than counting vertices, so they fail for the reason the bug actually had:
//  a gap in the disc.
//

#if os(macOS)
import CoreGraphics
import Foundation
import Testing
import simd

@testable import SwiftTerm

@Suite("Metal ellipse fan closure")
struct VTGMetalEllipseFanTests {

    private let center = VTGPoint(x: 100, y: 100)

    /// One triangle of the fan: the centre, plus the two rim points it spans.
    ///
    /// Named rather than a tuple because every use here cares which vertex is
    /// the apex — the rim pair is what sweeps an angle, the apex is shared by
    /// every triangle and is the origin the probes measure from.
    private struct Wedge {
        var apex: SIMD2<Float>
        var rimStart: SIMD2<Float>
        var rimEnd: SIMD2<Float>

        /// Whether `point` lies inside, by the sign-of-cross-products test.
        func contains(_ point: SIMD2<Float>) -> Bool {
            func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
                (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
            }
            let d1 = cross(apex, rimStart, point)
            let d2 = cross(rimStart, rimEnd, point)
            let d3 = cross(rimEnd, apex, point)
            let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
            let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
            return !(hasNegative && hasPositive)
        }
    }

    /// The triangles the renderer emits for a filled ellipse.
    private func fan(rx: Double, ry: Double) -> [Wedge] {
        var vertices: [ColorVertex] = []
        VTGMetalPrimitiveRenderer.appendEllipse(
            center: center,
            rx: rx,
            ry: ry,
            stroke: nil,
            fill: SIMD4<Float>(1, 1, 1, 1),
            lineWidth: 0,
            scale: 1,
            drawableHeight: 400,
            vertices: &vertices
        )
        return stride(from: 0, to: max(0, vertices.count - 2), by: 3).map {
            Wedge(apex: vertices[$0].position,
                  rimStart: vertices[$0 + 1].position,
                  rimEnd: vertices[$0 + 2].position)
        }
    }

    /// Directions around the disc that no triangle in `fan` covers.
    ///
    /// Probing *coverage* rather than vertex positions is the point: an
    /// unclosed fan still emits every rim point, so the missing wedge is
    /// invisible to anything that only inspects the vertex list. It is only
    /// visible as area nothing fills.
    private func uncoveredAngles(in fan: [Wedge], samples: Int = 720) -> [Double] {
        guard let apex = fan.first?.apex else { return [] }
        let reach = fan.flatMap { [$0.rimStart, $0.rimEnd] }
            .map { simd_distance($0, apex) }
            .max() ?? 0

        return (0..<samples).compactMap { step in
            let angle = Double(step) / Double(samples) * .pi * 2
            let probe = apex + SIMD2<Float>(
                Float(cos(angle)) * reach * 0.3,
                Float(sin(angle)) * reach * 0.3
            )
            return fan.contains(where: { $0.contains(probe) }) ? nil : angle
        }
    }

    @Test("A filled circle covers every direction from its centre")
    func filledCircleCoversTheDisc() {
        let uncovered = uncoveredAngles(in: fan(rx: 40, ry: 40))
        let firstGap = uncovered.first.map { $0 * 180 / .pi } ?? 0
        #expect(uncovered.isEmpty,
                "no triangle covers \(uncovered.count) of 720 directions, starting at \(firstGap)°")
    }

    @Test("An ellipse covers every direction too — it shares the same code")
    func filledEllipseCoversTheDisc() {
        #expect(uncoveredAngles(in: fan(rx: 60, ry: 25)).isEmpty)
    }

    @Test("The probe finds a gap when the fan is left open")
    func theProbeDetectsAnOpenFan() {
        // Guards the test itself: an open fan is exactly the emitted triangles
        // minus the wrapping one, and that must read as uncovered area — or
        // the tests above would pass against the bug they exist to catch.
        let open = Array(fan(rx: 40, ry: 40).dropLast())
        let uncovered = uncoveredAngles(in: open)
        #expect(!uncovered.isEmpty, "dropping the wrapping triangle must leave a visible wedge")
    }

    @Test("A zero-radius circle emits nothing rather than degenerate triangles")
    func zeroRadiusEmitsNothing() {
        var vertices: [ColorVertex] = []
        VTGMetalPrimitiveRenderer.appendEllipse(
            center: center, rx: 0, ry: 0,
            stroke: nil, fill: SIMD4<Float>(1, 1, 1, 1), lineWidth: 0,
            scale: 1, drawableHeight: 400, vertices: &vertices
        )
        #expect(vertices.isEmpty)
    }
}
#endif
