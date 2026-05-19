#if os(macOS)
import Foundation

extension LocalProcessVectorTerminalView {
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
