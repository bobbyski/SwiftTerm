#if os(macOS)
import Foundation

extension LocalProcessVectorTerminalView {
    /// Export the current terminal plus VTG overlay as an SVG debug snapshot.
    ///
    /// Writes a timestamped file to the Desktop, which is what the interactive
    /// menu command wants. Use ``exportSVGSnapshot(to:)`` when the destination
    /// matters — comparing two terminals needs predictable file names.
    public func exportSVGSnapshot() {
        _ = exportSVGSnapshot(to: nil)
    }

    /// Export the snapshot to a chosen file, returning where it landed.
    ///
    /// - Parameter url: The destination, or nil for a timestamped Desktop file.
    /// - Returns: The written file, or nil if rendering or writing failed.
    @discardableResult
    public func exportSVGSnapshot(to url: URL?) -> URL? {
        let previousMode = rendererMode
        defer { try? setRendererMode(previousMode) }
        do {
            try setRendererMode(.svg)
            let svg = makeSVGSnapshot { [vtgSession, weak self] context in
                let canvas = self?.currentVTGCanvas() ?? VTGCanvasSize(width: 0, height: 0)
                context.appendRawSVG(vtgSession.controller.scene.makeSVGFragment(
                    canvasWidth: Double(canvas.width),
                    canvasHeight: Double(canvas.height)
                ))
            }
            let fileURL = try writeSVGSnapshot(svg, to: url)
            print("VectorTerminal SVG snapshot: \(fileURL.path)")
            return fileURL
        } catch {
            print("VectorTerminal SVG snapshot failed: \(error)")
            return nil
        }
    }

    func writeSVGSnapshot(_ svg: String, to url: URL? = nil) throws -> URL {
        let fileURL = url ?? defaultSnapshotURL()
        // A chosen path may name a directory that does not exist yet, which is
        // ordinary when a capture run writes into a fresh results folder.
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try svg.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func defaultSnapshotURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "VectorTerminal-\(formatter.string(from: Date())).svg"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
#endif
