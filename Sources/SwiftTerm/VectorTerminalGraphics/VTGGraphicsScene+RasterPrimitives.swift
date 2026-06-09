import Foundation

/// Raster command parsing for the retained VTG scene.
extension VTGGraphicsScene {
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
            base64: payload,
            filter: command.spriteFilter()
        )
    }
}
