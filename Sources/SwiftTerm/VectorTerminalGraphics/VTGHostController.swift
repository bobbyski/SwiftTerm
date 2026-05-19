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
    let now: () -> Date
    private var lastReportedCanvas: VTGCanvasSize?
    var pendingFrame: PendingFrame?

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
            if let timeoutResponse = expirePendingFrameIfNeeded() {
                responses.append(timeoutResponse)
            }
            responses.append(contentsOf: responsesForCommand(command, canvas: canvas))
            let frameResult = handleFrameCommand(command)
            if let frameResponse = frameResult.response {
                responses.append(frameResponse)
            }
            if frameResult.handled {
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

    /// Return a VTG mouse response when the current mouse mode accepts `type`.
    public func mouseResponse(
        type: VTGMouseEventType,
        button: Int,
        snapshot: VTGMouseSnapshot,
        canvas: VTGCanvasSize? = nil,
        scrollX: Int? = nil,
        scrollY: Int? = nil
    ) -> String? {
        _ = expirePendingFrameIfNeeded()
        guard sendsMouseEvents, acceptsMouseEvent(type: type) else {
            return nil
        }
        let point = VTGPoint(x: Double(snapshot.x), y: Double(snapshot.y))
        let viewportPosition = canvas.flatMap {
            scene.viewportMousePosition(at: point, canvasWidth: Double($0.width), canvasHeight: Double($0.height))
        }
        let hit = canvas.flatMap {
            scene.hitRegion(at: point, canvasWidth: Double($0.width), canvasHeight: Double($0.height))
        } ?? scene.hitRegion(at: point)
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
                targetID: hit?.target,
                viewportLayer: viewportPosition?.layer,
                virtualX: viewportPosition.map { Int($0.x.rounded(.down)) },
                virtualY: viewportPosition.map { Int($0.y.rounded(.down)) }
            )
        )
    }

    /// Return a VTG mouse response for callers that still pass raw event names.
    public func mouseResponse(
        type: String,
        button: Int,
        snapshot: VTGMouseSnapshot,
        canvas: VTGCanvasSize? = nil,
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
            canvas: canvas,
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

    struct PendingFrame {
        var id: String
        var deadline: Date
        var scene: VTGGraphicsScene
    }

    struct FrameCommandResult {
        var handled: Bool
        var response: String?
    }
}
