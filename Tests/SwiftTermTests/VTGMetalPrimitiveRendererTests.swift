#if os(macOS)
import Foundation
import Testing

@testable import SwiftTerm

final class VTGMetalPrimitiveRendererTests {
    @Test func roundedUnderTextRectProducesMetalVertices() {
        let plan = VTGRenderPlan(
            canvas: VTGRenderCanvas(width: 240, height: 180),
            plane: .underText,
            entries: [
                VTGRenderPlanEntry(
                    primitive: .rect(
                        id: "rounded",
                        x: 10,
                        y: 20,
                        width: 90,
                        height: 50,
                        radius: 12,
                        corners: "12",
                        stroke: VTGColor(red: 0, green: 1, blue: 0),
                        fill: VTGColor(red: 0, green: 1, blue: 0, alpha: 0.25),
                        lineWidth: 2,
                        lineJoin: nil
                    ),
                    layer: VTGLayerModel.underTextLayer,
                    alpha: 1,
                    offset: .zero,
                    clip: nil,
                    viewport: nil
                )
            ]
        )

        let vertices = VTGMetalPrimitiveRenderer.makeVertices(plan: plan, scale: 1, drawableHeight: 180)

        #expect(vertices.count > 6)
    }

    @Test func roundedUnderTextTriangleProducesMetalVertices() {
        let plan = VTGRenderPlan(
            canvas: VTGRenderCanvas(width: 240, height: 180),
            plane: .underText,
            entries: [
                VTGRenderPlanEntry(
                    primitive: .triangle(
                        id: "rounded-triangle",
                        p1: VTGPoint(x: 40, y: 30),
                        p2: VTGPoint(x: 120, y: 130),
                        p3: VTGPoint(x: 20, y: 140),
                        radius: 14,
                        stroke: VTGColor(red: 0, green: 1, blue: 1),
                        fill: VTGColor(red: 0, green: 1, blue: 1, alpha: 0.2),
                        lineWidth: 2,
                        lineJoin: nil
                    ),
                    layer: VTGLayerModel.underTextLayer,
                    alpha: 1,
                    offset: .zero,
                    clip: nil,
                    viewport: nil
                )
            ]
        )

        let vertices = VTGMetalPrimitiveRenderer.makeVertices(plan: plan, scale: 1, drawableHeight: 180)

        #expect(vertices.count > 3)
    }

    @Test func textPlaneVectorSubsetProducesMetalVertices() {
        let plan = VTGRenderPlan(
            canvas: VTGRenderCanvas(width: 240, height: 180),
            plane: .textPlane,
            entries: [
                VTGRenderPlanEntry(
                    primitive: .line(
                        id: "text-plane-line",
                        x1: 20,
                        y1: 30,
                        x2: 180,
                        y2: 120,
                        stroke: VTGColor(red: 0, green: 1, blue: 0),
                        width: 3,
                        lineCap: nil
                    ),
                    layer: VTGLayerModel.textPlaneLayer,
                    alpha: 1,
                    offset: .zero,
                    clip: nil,
                    viewport: nil
                ),
                VTGRenderPlanEntry(
                    primitive: .rect(
                        id: "text-plane-rect",
                        x: 40,
                        y: 50,
                        width: 90,
                        height: 50,
                        radius: 10,
                        corners: "12",
                        stroke: VTGColor(red: 0, green: 1, blue: 1),
                        fill: VTGColor(red: 0, green: 1, blue: 1, alpha: 0.2),
                        lineWidth: 2,
                        lineJoin: nil
                    ),
                    layer: VTGLayerModel.textPlaneLayer,
                    alpha: 1,
                    offset: .zero,
                    clip: nil,
                    viewport: nil
                )
            ]
        )

        let vertices = VTGMetalPrimitiveRenderer.makeVertices(plan: plan, scale: 1, drawableHeight: 180)

        #expect(vertices.count > 6)
    }
}
#endif
