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

    /// The triangles the renderer emits for a filled ellipse.
    private func triangles(rx: Double, ry: Double) -> [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] {
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
        return stride(from: 0, to: vertices.count - 2, by: 3).map {
            (vertices[$0].position, vertices[$0 + 1].position, vertices[$0 + 2].position)
        }
    }

    private func contains(_ triangle: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>),
                          _ point: SIMD2<Float>) -> Bool {
        func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        let d1 = cross(triangle.0, triangle.1, point)
        let d2 = cross(triangle.1, triangle.2, point)
        let d3 = cross(triangle.2, triangle.0, point)
        let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
        let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNegative && hasPositive)
    }

    /// Directions around the disc that no emitted triangle covers.
    ///
    /// Probing *coverage* rather than vertex positions is the point: an
    /// unclosed fan still emits every rim point, so the missing wedge is
    /// invisible to anything that only inspects the vertex list. It is only
    /// visible as area nothing fills.
    private func uncoveredAngles(rx: Double, ry: Double, samples: Int = 720) -> [Double] {
        let fan = triangles(rx: rx, ry: ry)
        guard let apex = fan.first?.0 else { return [] }
        let reach = fan.flatMap { [$0.1, $0.2] }
            .map { simd_distance($0, apex) }
            .max() ?? 0

        return (0..<samples).compactMap { step in
            let angle = Double(step) / Double(samples) * .pi * 2
            let probe = apex + SIMD2<Float>(
                Float(cos(angle)) * reach * 0.3,
                Float(sin(angle)) * reach * 0.3
            )
            return fan.contains(where: { contains($0, probe) }) ? nil : angle
        }
    }

    @Test("A filled circle covers every direction from its centre")
    func filledCircleCoversTheDisc() {
        let uncovered = uncoveredAngles(rx: 40, ry: 40)
        let firstGap = uncovered.first.map { $0 * 180 / .pi } ?? 0
        #expect(uncovered.isEmpty,
                "no triangle covers \(uncovered.count) of 720 directions, starting at \(firstGap)°")
    }

    @Test("An ellipse covers every direction too — it shares the same code")
    func filledEllipseCoversTheDisc() {
        #expect(uncoveredAngles(rx: 60, ry: 25).isEmpty)
    }

    @Test("The probe finds a gap when the fan is left open")
    func theProbeDetectsAnOpenFan() {
        // Guards the test itself: an open fan is exactly the emitted triangles
        // minus the wrapping one, and that must read as uncovered area — or
        // the tests above would pass against the bug they exist to catch.
        let fan = triangles(rx: 40, ry: 40)
        let open = Array(fan.dropLast())
        guard let apex = open.first?.0 else {
            Issue.record("no triangles")
            return
        }
        let reach = open.flatMap { [$0.1, $0.2] }.map { simd_distance($0, apex) }.max() ?? 0

        let uncovered = (0..<720).filter { step in
            let angle = Double(step) / 720 * .pi * 2
            let probe = apex + SIMD2<Float>(
                Float(cos(angle)) * reach * 0.3,
                Float(sin(angle)) * reach * 0.3
            )
            return !open.contains(where: { contains($0, probe) })
        }
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
