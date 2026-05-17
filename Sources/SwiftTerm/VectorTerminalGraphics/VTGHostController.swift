import Foundation

/// Host-side controller for VectorTerminal Graphics protocol state.
///
/// `VTGHostController` owns the framework-level parts of VTG integration:
/// parsing private APC callbacks, mutating the retained scene, tracking
/// resize/mouse subscriptions, and encoding host responses. Embedding views
/// still own platform facts: current canvas size, AppKit/UI events, and writing
/// response bytes to the child process.
public final class VTGHostController {
    public let scene = VTGGraphicsScene()

    private let parser = VectorTerminalGraphicsParser()
    private let now: () -> Date
    private var lastReportedCanvas: VTGCanvasSize?
    private var pendingFrame: PendingFrame?

    public private(set) var sendsResizeEvents = false
    public private(set) var sendsMouseEvents = false
    public private(set) var mouseMode: VTGMouseMode = .click

    /// Whether a graphics-only offscreen frame is currently buffering VTG
    /// scene mutations.
    public var hasPendingFrame: Bool {
        pendingFrame != nil
    }

    /// Identifier of the current pending offscreen frame, if one exists.
    public var pendingFrameID: String? {
        pendingFrame?.id
    }

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Parse and apply a SwiftTerm private sequence.
    ///
    /// Returns `nil` when the sequence is not VTG. Returns an empty array when
    /// it was VTG but produced no immediate host response.
    public func handlePrivateSequence(
        _ sequence: TerminalPrivateSequence,
        canvas: VTGCanvasSize
    ) -> [String]? {
        guard let command = parser.command(from: sequence) else {
            return nil
        }
        return process([command], canvas: canvas)
    }

    /// Apply parsed VTG commands and return immediate host responses.
    public func process(
        _ commands: [VectorTerminalGraphicsCommand],
        canvas: VTGCanvasSize
    ) -> [String] {
        var responses: [String] = []
        for command in commands {
            expirePendingFrameIfNeeded()
            responses.append(contentsOf: responsesForCommand(command, canvas: canvas))
            guard handleFrameCommand(command) == false else {
                continue
            }
            activeScene.apply(command)
        }
        return responses
    }

    /// Discard an active pending graphics frame.
    ///
    /// Embedding views should call this when a child process exits, a local
    /// session resets, or the host needs to recover before the frame timeout
    /// fires. The visible retained scene is left unchanged.
    public func discardPendingFrame() {
        pendingFrame = nil
    }

    /// Return a resize event response when the subscribed client should be told.
    public func resizeResponseIfNeeded(
        canvas: VTGCanvasSize,
        force: Bool = false,
        processRunning: Bool = true
    ) -> String? {
        expirePendingFrameIfNeeded()
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

    /// Return a VTG mouse response when the current mouse mode accepts `type`.
    public func mouseResponse(
        type: VTGMouseEventType,
        button: Int,
        snapshot: VTGMouseSnapshot,
        scrollX: Int? = nil,
        scrollY: Int? = nil
    ) -> String? {
        expirePendingFrameIfNeeded()
        guard sendsMouseEvents, acceptsMouseEvent(type: type) else {
            return nil
        }
        let hit = scene.hitRegion(at: VTGPoint(x: Double(snapshot.x), y: Double(snapshot.y)))
        return VTGResponseEncoder.mouse(
            VTGMouseEventPayload(
                type: type.rawValue,
                button: button,
                x: snapshot.x,
                y: snapshot.y,
                cellX: snapshot.cellX,
                cellY: snapshot.cellY,
                modifiers: snapshot.modifiers,
                scrollX: scrollX,
                scrollY: scrollY,
                hitID: hit?.id,
                targetID: hit?.target
            )
        )
    }

    /// Return a VTG mouse response for callers that still pass raw event names.
    public func mouseResponse(
        type: String,
        button: Int,
        snapshot: VTGMouseSnapshot,
        scrollX: Int? = nil,
        scrollY: Int? = nil
    ) -> String? {
        guard let type = VTGMouseEventType(rawValue: type) else {
            return nil
        }
        return mouseResponse(
            type: type,
            button: button,
            snapshot: snapshot,
            scrollX: scrollX,
            scrollY: scrollY
        )
    }

    private func responsesForCommand(
        _ command: VectorTerminalGraphicsCommand,
        canvas: VTGCanvasSize
    ) -> [String] {
        switch command.name {
        case "capabilities?":
            return [VTGResponseEncoder.capabilities(canvas: canvas)]
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

    private var activeScene: VTGGraphicsScene {
        pendingFrame?.scene ?? scene
    }

    private func handleFrameCommand(_ command: VectorTerminalGraphicsCommand) -> Bool {
        switch command.name {
        case "startFrame":
            startFrame(command)
            return true
        case "endFrame":
            endFrame(command)
            return true
        case "cancelFrame":
            cancelFrame(command)
            return true
        default:
            return false
        }
    }

    private func startFrame(_ command: VectorTerminalGraphicsCommand) {
        let frameID = frameID(from: command)
        pendingFrame = PendingFrame(
            id: frameID,
            deadline: now().addingTimeInterval(timeoutInterval(from: command)),
            scene: scene.makeSnapshot()
        )
    }

    private func endFrame(_ command: VectorTerminalGraphicsCommand) {
        guard let pendingFrame,
              frameIDMatches(command, pendingFrame: pendingFrame) else {
            return
        }
        scene.replaceContents(with: pendingFrame.scene)
        self.pendingFrame = nil
    }

    private func cancelFrame(_ command: VectorTerminalGraphicsCommand) {
        guard let pendingFrame,
              frameIDMatches(command, pendingFrame: pendingFrame) else {
            return
        }
        self.pendingFrame = nil
    }

    private func expirePendingFrameIfNeeded() {
        guard let pendingFrame,
              now() >= pendingFrame.deadline else {
            return
        }
        self.pendingFrame = nil
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

    private func timeoutInterval(from command: VectorTerminalGraphicsCommand) -> TimeInterval {
        let rawMilliseconds = command.parameters["timeout"].flatMap(Double.init) ?? 250
        let clampedMilliseconds = min(10_000, max(1, rawMilliseconds))
        return clampedMilliseconds / 1_000
    }

    private func acceptsMouseEvent(type: VTGMouseEventType) -> Bool {
        switch mouseMode {
        case .click:
            return type == .click
        case .raw:
            return type == .down || type == .up || type == .click || type == .scroll
        case .drag:
            return type == .down || type == .up || type == .drag || type == .click || type == .scroll
        case .all:
            return true
        }
    }

    private struct PendingFrame {
        var id: String
        var deadline: Date
        var scene: VTGGraphicsScene
    }
}
