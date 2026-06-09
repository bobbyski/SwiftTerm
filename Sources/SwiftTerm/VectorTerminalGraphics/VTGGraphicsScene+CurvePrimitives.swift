import Foundation

/// Curve command parsing for the retained VTG scene.
extension VTGGraphicsScene {
    func parseCurve(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        let start = VTGPoint(x: command.double("x1"), y: command.double("y1"))
        let end = VTGPoint(x: command.double("x2"), y: command.double("y2"))
        let curve: VTGCurve
        switch command.parameters["kind"] {
        case "cubic":
            curve = .cubic(
                start: start,
                control1: VTGPoint(x: command.double("c1x"), y: command.double("c1y")),
                control2: VTGPoint(x: command.double("c2x"), y: command.double("c2y")),
                end: end
            )
        default:
            curve = .quadratic(
                start: start,
                control: VTGPoint(x: command.double("cx"), y: command.double("cy")),
                end: end
            )
        }
        return .curve(
            id: id,
            curve: curve,
            stroke: command.color("stroke") ?? .foreground,
            width: max(1, command.double("width", default: 1)),
            lineCap: command.lineCap(),
            lineJoin: command.lineJoin()
        )
    }
}
