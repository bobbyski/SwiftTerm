import Foundation

extension VTGHostController {
    /// Return a resize event response when the subscribed client should be told.
    public func resizeResponseIfNeeded(
        canvas: VTGCanvasSize,
        force: Bool = false,
        processRunning: Bool = true
    ) -> String? {
        _ = expirePendingFrameIfNeeded()
        guard sendsResizeEvents, processRunning else {
            return nil
        }
        guard canvas.width > 0, canvas.height > 0 else {
            return nil
        }
        guard force || canvas != lastReportedCanvas else {
            return nil
        }
        lastReportedCanvas = canvas
        return VTGResponseEncoder.resize(canvas: canvas)
    }

    func responsesForCommand(
        _ command: VectorTerminalGraphicsCommand,
        canvas: VTGCanvasSize,
        renderer: String = "overlay",
        glyphSize: (width: Double, height: Double)? = nil
    ) -> [String] {
        switch command.name {
        case "capabilities?":
            return [VTGResponseEncoder.capabilities(canvas: canvas, renderer: renderer)]
        case "canvas?":
            return [VTGResponseEncoder.canvasResponse(commandName: "canvas", canvas: canvas)]
        case "size?":
            return [VTGResponseEncoder.canvasResponse(commandName: "size", canvas: canvas)]
        case "graphicsVisible?":
            return [VTGResponseEncoder.graphicsVisible(isVisible: graphicsLayersVisible)]
        case "glyphSize?":
            guard let glyphSize else {
                return []
            }
            return [VTGResponseEncoder.glyphSize(width: glyphSize.width, height: glyphSize.height)]
        case "graphicsVisible":
            graphicsLayersVisible = parseEnabled(command.parameters)
            return []
        case "resizeEvents":
            sendsResizeEvents = parseEnabled(command.parameters)
            if sendsResizeEvents {
                lastReportedCanvas = canvas
                return [VTGResponseEncoder.resize(canvas: canvas)]
            }
            lastReportedCanvas = nil
            return []
        case "mouseEvents":
            sendsMouseEvents = parseEnabled(command.parameters)
            mouseMode = VTGMouseMode(rawValue: command.parameters["mode"] ?? "raw") ?? .raw
            return []
        default:
            return []
        }
    }

    private func parseEnabled(_ parameters: [String: String]) -> Bool {
        let rawValue = parameters["enabled"] ?? parameters["visible"] ?? "0"
        switch rawValue.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}
