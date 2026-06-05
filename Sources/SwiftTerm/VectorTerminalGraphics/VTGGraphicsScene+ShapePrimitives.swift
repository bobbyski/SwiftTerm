import Foundation

/// Shape and path command parsing for the retained VTG scene.
extension VTGGraphicsScene {
    func parseTriangle(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .triangle(
            id: id,
            p1: VTGPoint(x: command.double("x1"), y: command.double("y1")),
            p2: VTGPoint(x: command.double("x2"), y: command.double("y2")),
            p3: VTGPoint(x: command.double("x3"), y: command.double("y3")),
            radius: max(0, command.double("radius", default: 0)),
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("width", default: 1)),
            lineJoin: command.lineJoin()
        )
    }

    func parsePath(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"],
              let commands = VTGPathParser.parse(command.payload ?? ""),
              commands.isEmpty == false else {
            return nil
        }
        return .path(
            id: id,
            commands: commands,
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("width", default: 1)),
            lineCap: command.lineCap(),
            lineJoin: command.lineJoin()
        )
    }

    func parseRect(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .rect(
            id: id,
            x: command.double("x"),
            y: command.double("y"),
            width: command.double("w"),
            height: command.double("h"),
            radius: max(0, command.double("radius", default: 0)),
            corners: sanitizedRectCorners(command.parameters["corners"]),
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("width", default: 1)),
            lineJoin: command.lineJoin()
        )
    }

    func parseCircle(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .circle(
            id: id,
            cx: command.double("cx"),
            cy: command.double("cy"),
            radius: command.double("r"),
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("width", default: 1))
        )
    }

    func parseEllipse(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .ellipse(
            id: id,
            cx: command.double("cx"),
            cy: command.double("cy"),
            rx: command.double("rx"),
            ry: command.double("ry"),
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("width", default: 1))
        )
    }
}

private func sanitizedRectCorners(_ value: String?) -> String? {
    guard let value else {
        return nil
    }
    var seen = Set<Character>()
    let digits = value.compactMap { character -> Character? in
        guard "1234".contains(character), seen.insert(character).inserted else {
            return nil
        }
        return character
    }
    guard digits.isEmpty == false else {
        return nil
    }
    return String(digits)
}
