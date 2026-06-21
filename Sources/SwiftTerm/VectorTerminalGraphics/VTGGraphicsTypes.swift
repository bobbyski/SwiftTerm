import Foundation

/// A retained drawing primitive in the VectorTerminal overlay scene.
///
/// Each primitive has an ID so apps can redraw by replacing existing shapes
/// instead of clearing and repainting the entire canvas every frame.
public enum VTGPrimitive: Equatable {
    case pixel(id: String, x: Double, y: Double, color: VTGColor)
    case clearRect(id: String, x: Double, y: Double, width: Double, height: Double)
    case line(id: String, x1: Double, y1: Double, x2: Double, y2: Double, stroke: VTGColor, width: Double, lineCap: VTGLineCap?)
    case draw(id: String, points: [VTGPoint], stroke: VTGColor, width: Double, lineCap: VTGLineCap?, lineJoin: VTGLineJoin?)
    case curve(id: String, curve: VTGCurve, stroke: VTGColor, width: Double, lineCap: VTGLineCap?, lineJoin: VTGLineJoin?)
    case triangle(id: String, p1: VTGPoint, p2: VTGPoint, p3: VTGPoint, radius: Double, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double, lineJoin: VTGLineJoin?)
    case path(id: String, commands: [VTGPathCommand], stroke: VTGColor?, fill: VTGColor?, lineWidth: Double, lineCap: VTGLineCap?, lineJoin: VTGLineJoin?)
    case rect(id: String, x: Double, y: Double, width: Double, height: Double, radius: Double, corners: String?, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double, lineJoin: VTGLineJoin?)
    case circle(id: String, cx: Double, cy: Double, radius: Double, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double)
    case ellipse(id: String, cx: Double, cy: Double, rx: Double, ry: Double, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double)
    case text(id: String, x: Double, y: Double, value: String, color: VTGColor, size: Double)
    case image(id: String, x: Double, y: Double, width: Double, height: Double, format: String, data: Data, base64: String, filter: VTGSpriteFilter)
    case sprite(id: String, assetID: String, x: Double, y: Double, rotation: Double, scale: Double, anchorX: Double, anchorY: Double)

    public var id: String {
        switch self {
        case .pixel(let id, _, _, _),
             .clearRect(let id, _, _, _, _),
             .line(let id, _, _, _, _, _, _, _),
             .draw(let id, _, _, _, _, _),
             .curve(let id, _, _, _, _, _),
             .triangle(let id, _, _, _, _, _, _, _, _),
             .path(let id, _, _, _, _, _, _),
             .rect(let id, _, _, _, _, _, _, _, _, _, _),
             .circle(let id, _, _, _, _, _, _),
             .ellipse(let id, _, _, _, _, _, _, _),
             .text(let id, _, _, _, _, _),
             .image(let id, _, _, _, _, _, _, _, _),
             .sprite(let id, _, _, _, _, _, _, _):
            return id
        }
    }
}
