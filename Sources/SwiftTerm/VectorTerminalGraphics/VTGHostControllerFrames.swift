import Foundation

/// Offscreen frame lifecycle support for `VTGHostController`.
extension VTGHostController {
    var activeScene: VTGGraphicsScene {
        pendingFrame?.scene ?? scene
    }

    func handleFrameCommand(_ command: VectorTerminalGraphicsCommand) -> FrameCommandResult {
        switch command.name {
        case "startFrame":
            return FrameCommandResult(handled: true, response: startFrame(command))
        case "endFrame":
            return FrameCommandResult(handled: true, response: endFrame(command))
        case "cancelFrame":
            return FrameCommandResult(handled: true, response: cancelFrame(command))
        default:
            return FrameCommandResult(handled: false, response: nil)
        }
    }

    func startFrame(_ command: VectorTerminalGraphicsCommand) -> String {
        let frameID = frameID(from: command)
        let timeoutMilliseconds = timeoutMilliseconds(from: command)
        guard pendingFrame == nil else {
            return VTGResponseEncoder.frameEvent("frameRejected", id: frameID, reason: "nested")
        }
        pendingFrame = PendingFrame(
            id: frameID,
            deadline: now().addingTimeInterval(TimeInterval(timeoutMilliseconds) / 1_000),
            scene: scene.makeSnapshot()
        )
        return VTGResponseEncoder.frameEvent("frameStarted", id: frameID, timeoutMilliseconds: timeoutMilliseconds)
    }

    func endFrame(_ command: VectorTerminalGraphicsCommand) -> String? {
        guard let pendingFrame else {
            return nil
        }
        guard frameIDMatches(command, pendingFrame: pendingFrame) else {
            return VTGResponseEncoder.frameEvent("frameRejected", id: frameID(from: command), reason: "idMismatch")
        }
        scene.replaceContents(with: pendingFrame.scene)
        self.pendingFrame = nil
        return VTGResponseEncoder.frameEvent("frameCommitted", id: pendingFrame.id)
    }

    func cancelFrame(_ command: VectorTerminalGraphicsCommand) -> String? {
        guard let pendingFrame else {
            return nil
        }
        guard frameIDMatches(command, pendingFrame: pendingFrame) else {
            return VTGResponseEncoder.frameEvent("frameRejected", id: frameID(from: command), reason: "idMismatch")
        }
        self.pendingFrame = nil
        return VTGResponseEncoder.frameEvent("frameCanceled", id: pendingFrame.id, reason: "app")
    }

    func expirePendingFrameIfNeeded() -> String? {
        guard let pendingFrame,
              now() >= pendingFrame.deadline else {
            return nil
        }
        self.pendingFrame = nil
        return VTGResponseEncoder.frameEvent("frameTimeout", id: pendingFrame.id, reason: "timeout")
    }

    private func frameID(from command: VectorTerminalGraphicsCommand) -> String {
        let value = command.parameters["id"] ?? "default"
        return value.isEmpty ? "default" : value
    }

    private func frameIDMatches(_ command: VectorTerminalGraphicsCommand, pendingFrame: PendingFrame) -> Bool {
        guard let requestedID = command.parameters["id"], requestedID.isEmpty == false else {
            return true
        }
        return requestedID == pendingFrame.id
    }

    private func timeoutMilliseconds(from command: VectorTerminalGraphicsCommand) -> Int {
        let rawMilliseconds = command.parameters["timeout"].flatMap(Double.init) ?? 250
        return Int(min(10_000, max(1, rawMilliseconds)))
    }
}
