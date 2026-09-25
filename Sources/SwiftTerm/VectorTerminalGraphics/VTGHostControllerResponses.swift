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
        let reported = reportedCanvas(for: canvas)
        guard force || reported != lastReportedCanvas else {
            return nil
        }
        lastReportedCanvas = reported
        return VTGResponseEncoder.resize(canvas: reported)
    }

    func responsesForCommand(
        _ command: VectorTerminalGraphicsCommand,
        canvas: VTGCanvasSize,
        renderer: String = "overlay",
        glyphSize: (width: Double, height: Double)? = nil
    ) -> [String] {
        switch command.name {
        case "capabilities?":
            return [VTGResponseEncoder.capabilities(canvas: screenCanvas(for: canvas), renderer: renderer)]
        case "canvas?":
            return [VTGResponseEncoder.canvasResponse(commandName: "canvas", canvas: reportedCanvas(for: canvas))]
        case "size?":
            return [VTGResponseEncoder.canvasResponse(commandName: "size", canvas: reportedCanvas(for: canvas))]
        case "graphicsVisible?":
            return [VTGResponseEncoder.graphicsVisible(isVisible: graphicsLayersVisible)]
        case "glyphSize?":
            guard let glyphSize = screenGlyphSize(glyphSize) else {
                return []
            }
            return [VTGResponseEncoder.glyphSize(width: glyphSize.width, height: glyphSize.height)]
        case "screenLock":
            return screenLockResponses(command, canvas: canvas)
        case "screenUnlock":
            return screenUnlockResponses(canvas: canvas)
        case "screen?":
            return [VTGResponseEncoder.screen(
                fields: screenLock?.responseFields(layout: screenLayout(inFrame: canvas)) ?? []
            )]
        case "graphicsVisible":
            graphicsLayersVisible = parseEnabled(command.parameters)
            return []
        case "rasterMode":
            setRasterMode(parseEnabled(command.parameters))
            return []
        case "linkDetection":
            var settings = linkDetectionSettings
            settings.isEnabled = parseEnabled(command.parameters)
            if command.parameters["decorate"] != nil {
                settings.decoratesLinks = parseEnabled(command.parameters, key: "decorate")
            }
            if let rawColor = command.parameters["color"], let color = VTGColor(hex: rawColor) {
                settings.color = color
            }
            linkDetectionSettings = settings
            return []
        case "resizeEvents":
            sendsResizeEvents = parseEnabled(command.parameters)
            if sendsResizeEvents {
                let reported = reportedCanvas(for: canvas)
                lastReportedCanvas = reported
                return [VTGResponseEncoder.resize(canvas: reported)]
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
        parseEnabled(parameters, key: "enabled", fallbackKey: "visible")
    }

    private func parseEnabled(
        _ parameters: [String: String],
        key: String,
        fallbackKey: String? = nil
    ) -> Bool {
        let rawValue = parameters[key] ?? fallbackKey.flatMap { parameters[$0] } ?? "0"
        switch rawValue.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}
