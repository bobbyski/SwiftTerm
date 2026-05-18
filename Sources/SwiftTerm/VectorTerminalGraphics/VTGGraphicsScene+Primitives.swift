import Foundation

/// Primitive command parsing for the retained VTG scene.
extension VTGGraphicsScene {
    func parsePixel(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .pixel(
            id: id,
            x: command.double("x"),
            y: command.double("y"),
            color: command.color("color") ?? command.color("fill") ?? .foreground
        )
    }

    func parseLine(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .line(
            id: id,
            x1: command.double("x1"),
            y1: command.double("y1"),
            x2: command.double("x2"),
            y2: command.double("y2"),
            stroke: command.color("stroke") ?? .foreground,
            width: max(1, command.double("width", default: 1))
        )
    }

    func parseDraw(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        // `draw` carries its arbitrary point list in the APC payload:
        // `x,y x,y x,y`. Keeping the large list out of comma parameters makes
        // the command easier to stream and easier for non-Swift clients to emit.
        let points = (command.payload ?? "")
            .split(separator: " ", omittingEmptySubsequences: true)
            .compactMap { pair -> VTGPoint? in
                let coordinates = pair.split(separator: ",", maxSplits: 1)
                guard coordinates.count == 2,
                      let x = Double(coordinates[0]),
                      let y = Double(coordinates[1]) else {
                    return nil
                }
                return VTGPoint(x: x, y: y)
            }
        guard points.count >= 2 else {
            return nil
        }
        return .draw(
            id: id,
            points: points,
            stroke: command.color("stroke") ?? .foreground,
            width: max(1, command.double("width", default: 1))
        )
    }

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
            width: max(1, command.double("width", default: 1))
        )
    }

    func parseTriangle(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .triangle(
            id: id,
            p1: VTGPoint(x: command.double("x1"), y: command.double("y1")),
            p2: VTGPoint(x: command.double("x2"), y: command.double("y2")),
            p3: VTGPoint(x: command.double("x3"), y: command.double("y3")),
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("width", default: 1))
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
            lineWidth: max(1, command.double("width", default: 1))
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
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("width", default: 1))
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

    func parseText(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .text(
            id: id,
            x: command.double("x"),
            y: command.double("y"),
            value: command.payload ?? "",
            color: command.color("color") ?? .foreground,
            size: max(1, command.double("size", default: 14))
        )
    }

    func parseImage(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"],
              let payload = command.payload,
              let data = Data(base64Encoded: payload) else {
            return nil
        }
        let format = command.parameters["format"] ?? "png"
        let width = command.double("width", default: command.double("w"))
        let height = command.double("height", default: command.double("h"))
        guard width > 0, height > 0 else {
            return nil
        }
        return .image(
            id: id,
            x: command.double("x"),
            y: command.double("y"),
            width: width,
            height: height,
            format: format,
            data: data,
            base64: payload
        )
    }
}
