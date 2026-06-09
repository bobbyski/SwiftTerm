#if os(macOS)
import Foundation

extension LocalProcessVectorTerminalView {
    /// Export the current terminal plus VTG overlay as an SVG debug snapshot.
    public func exportSVGSnapshot() {
        let previousMode = rendererMode
        do {
            try setRendererMode(.svg)
            let svg = makeSVGSnapshot { [vtgSession, weak self] context in
                let canvas = self?.currentVTGCanvas() ?? VTGCanvasSize(width: 0, height: 0)
                context.appendRawSVG(vtgSession.controller.scene.makeSVGFragment(
                    canvasWidth: Double(canvas.width),
                    canvasHeight: Double(canvas.height)
                ))
            }
            let fileURL = try writeSVGSnapshot(svg)
            print("VectorTerminal SVG snapshot: \(fileURL.path)")
        } catch {
            print("VectorTerminal SVG snapshot failed: \(error)")
        }
        try? setRendererMode(previousMode)
    }

    func writeSVGSnapshot(_ svg: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "VectorTerminal-\(formatter.string(from: Date())).svg"
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        let fileURL = directory.appendingPathComponent(fileName)
        try svg.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
#endif
