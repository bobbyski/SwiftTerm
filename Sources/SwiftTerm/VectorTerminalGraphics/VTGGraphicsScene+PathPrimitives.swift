import Foundation

/// Path command parsing for the retained VTG scene.
extension VTGGraphicsScene {
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
}
