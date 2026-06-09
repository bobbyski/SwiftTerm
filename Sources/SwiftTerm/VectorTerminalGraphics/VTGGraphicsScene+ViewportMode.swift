import Foundation

/// Fixed-resolution viewport mutation helpers for overlay layers.
extension VTGGraphicsScene {
    func setViewportMode(_ command: VectorTerminalGraphicsCommand) {
        let layer = command.layerValue(default: defaultLayer)
        guard VTGLayerModel.isScrollable(layer) else {
            return
        }

        let rawMode = command.parameters["value"] ?? command.parameters["mode"]
        if rawMode == "native" || rawMode == "off" || rawMode == "none" {
            viewportModes.removeValue(forKey: layer)
            viewportScales.removeValue(forKey: layer)
            return
        }

        let width = command.double("width", default: command.double("w"))
        let height = command.double("height", default: command.double("h"))
        guard width > 0, height > 0 else {
            return
        }
        let rawScale = command.parameters["scale"] ?? "fit"
        guard let scaleMode = VTGViewportMode.ScaleMode(rawValue: rawScale) else {
            return
        }
        viewportModes[layer] = VTGViewportMode(
            layer: layer,
            width: width,
            height: height,
            scaleMode: scaleMode
        )
    }

    func setViewportScale(_ command: VectorTerminalGraphicsCommand) {
        let layer = command.layerValue(default: defaultLayer)
        guard VTGLayerModel.isScrollable(layer), viewportModes[layer] != nil else {
            return
        }
        let scale = command.double("scale", default: 1)
        guard scale > 0 else {
            return
        }
        viewportScales[layer] = VTGViewportScale(
            layer: layer,
            scale: scale,
            x: command.double("x", default: viewportScales[layer]?.x ?? 0),
            y: command.double("y", default: viewportScales[layer]?.y ?? 0)
        )
    }
}
