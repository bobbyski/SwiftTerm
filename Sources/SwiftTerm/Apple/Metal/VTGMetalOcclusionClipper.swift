#if os(macOS)
import CoreGraphics
import Foundation

/// Clips Metal VTG triangles to the visible part of a text mask
/// (WINDOW_PLAN.md Phase 1).
///
/// ```text
///   triangle            visible rects             result
///      /\              ┌────┐      ┌───┐           /|      |\
///     /  \      ∩      │    │ hole │   │    =     /_|      |_\
///    /____\            └────┘      └───┘
/// ```
///
/// The Metal primitive path draws plain colored triangles, so masking can be
/// done on the CPU before upload: each triangle is cut against each visible
/// rectangle it touches (Sutherland–Hodgman against four axis-aligned edges)
/// and the pieces are fanned back into triangles. Only layers that asked for
/// `layerOcclude,by=ink` come through here.
enum VTGMetalOcclusionClipper {
    /// A visible rectangle in the vertex space the batches use: device pixels,
    /// y up from the bottom of the drawable.
    struct Box {
        var minX: Float
        var minY: Float
        var maxX: Float
        var maxY: Float
    }

    /// Visible rectangles in canvas points, converted to vertex space.
    static func boxes(visible: [VTGLayerClip], scale: CGFloat, drawableHeight: CGFloat) -> [Box] {
        visible.map { rect in
            Box(minX: Float(CGFloat(rect.x) * scale),
                minY: Float(drawableHeight - CGFloat(rect.y + rect.height) * scale),
                maxX: Float(CGFloat(rect.x + rect.width) * scale),
                maxY: Float(drawableHeight - CGFloat(rect.y) * scale))
        }
    }

    /// The parts of `vertices` (a triangle list) inside any of `boxes`.
    static func clip(_ vertices: [ColorVertex], to boxes: [Box]) -> [ColorVertex] {
        var output: [ColorVertex] = []
        var index = 0
        while index + 2 < vertices.count {
            let triangle = [vertices[index], vertices[index + 1], vertices[index + 2]]
            index += 3
            let minX = triangle.map(\.position.x).min()!
            let maxX = triangle.map(\.position.x).max()!
            let minY = triangle.map(\.position.y).min()!
            let maxY = triangle.map(\.position.y).max()!
            for box in boxes where box.maxX > minX && box.minX < maxX && box.maxY > minY && box.minY < maxY {
                if box.minX <= minX && box.maxX >= maxX && box.minY <= minY && box.maxY >= maxY {
                    output.append(contentsOf: triangle)
                    continue
                }
                let polygon = clipPolygon(triangle, to: box)
                guard polygon.count >= 3 else { continue }
                for fan in 1..<(polygon.count - 1) {
                    output.append(polygon[0])
                    output.append(polygon[fan])
                    output.append(polygon[fan + 1])
                }
            }
        }
        return output
    }

    private static func clipPolygon(_ polygon: [ColorVertex], to box: Box) -> [ColorVertex] {
        var result = polygon
        result = clipEdge(result) { $0.position.x >= box.minX } intersect: { a, b in
            (box.minX - a.position.x) / (b.position.x - a.position.x)
        }
        result = clipEdge(result) { $0.position.x <= box.maxX } intersect: { a, b in
            (box.maxX - a.position.x) / (b.position.x - a.position.x)
        }
        result = clipEdge(result) { $0.position.y >= box.minY } intersect: { a, b in
            (box.minY - a.position.y) / (b.position.y - a.position.y)
        }
        result = clipEdge(result) { $0.position.y <= box.maxY } intersect: { a, b in
            (box.maxY - a.position.y) / (b.position.y - a.position.y)
        }
        return result
    }

    /// One Sutherland–Hodgman pass against a single edge.
    private static func clipEdge(_ polygon: [ColorVertex],
                                 inside: (ColorVertex) -> Bool,
                                 intersect: (ColorVertex, ColorVertex) -> Float) -> [ColorVertex] {
        guard !polygon.isEmpty else { return [] }
        var output: [ColorVertex] = []
        for index in polygon.indices {
            let current = polygon[index]
            let previous = polygon[(index + polygon.count - 1) % polygon.count]
            let currentInside = inside(current)
            let previousInside = inside(previous)
            if currentInside {
                if !previousInside {
                    output.append(lerp(previous, current, intersect(previous, current)))
                }
                output.append(current)
            } else if previousInside {
                output.append(lerp(previous, current, intersect(previous, current)))
            }
        }
        return output
    }

    private static func lerp(_ a: ColorVertex, _ b: ColorVertex, _ t: Float) -> ColorVertex {
        ColorVertex(position: a.position + (b.position - a.position) * t,
                    color: a.color + (b.color - a.color) * t)
    }
}
#endif
