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
        renderer: String = "overlay"
    ) -> [String] {
        switch command.name {
        case "capabilities?":
            return [VTGResponseEncoder.capabilities(canvas: canvas, renderer: renderer)]
        case "canvas?":
            return [VTGResponseEncoder.canvasResponse(commandName: "canvas", canvas: canvas)]
        case "size?":
            return [VTGResponseEncoder.canvasResponse(commandName: "size", canvas: canvas)]
        case "resizeEvents":
            sendsResizeEvents = command.parameters["enabled"] == "1" ||
                command.parameters["enabled"] == "true"
            if sendsResizeEvents {
                lastReportedCanvas = canvas
                return [VTGResponseEncoder.resize(canvas: canvas)]
            }
            lastReportedCanvas = nil
            return []
        case "mouseEvents":
            sendsMouseEvents = command.parameters["enabled"] == "1" ||
                command.parameters["enabled"] == "true"
            mouseMode = VTGMouseMode(rawValue: command.parameters["mode"] ?? "raw") ?? .raw
            return []
        default:
            return []
        }
    }
}
