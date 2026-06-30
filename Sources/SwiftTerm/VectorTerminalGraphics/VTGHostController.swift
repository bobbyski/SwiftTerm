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
    var lastReportedCanvas: VTGCanvasSize?
    var pendingFrame: PendingFrame?

    public internal(set) var sendsResizeEvents = false
    public internal(set) var sendsMouseEvents = false
    public internal(set) var mouseMode: VTGMouseMode = .click
    public internal(set) var graphicsLayersVisible = true

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
        canvas: VTGCanvasSize,
        renderer: String = "overlay",
        glyphSize: (width: Double, height: Double)? = nil
    ) -> [String]? {
        guard let command = parser.command(from: sequence) else {
            return nil
        }
        return process([command], canvas: canvas, renderer: renderer, glyphSize: glyphSize)
    }

    /// Apply parsed VTG commands and return immediate host responses.
    public func process(
        _ commands: [VectorTerminalGraphicsCommand],
        canvas: VTGCanvasSize,
        renderer: String = "overlay",
        glyphSize: (width: Double, height: Double)? = nil
    ) -> [String] {
        var responses: [String] = []
        for command in commands {
            if let timeoutResponse = expirePendingFrameIfNeeded() {
                responses.append(timeoutResponse)
            }
            responses.append(contentsOf: responsesForCommand(command, canvas: canvas, renderer: renderer, glyphSize: glyphSize))
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

    /// Show or hide all VTG graphics layers without mutating retained objects.
    public func setGraphicsLayersVisible(_ isVisible: Bool) {
        graphicsLayersVisible = isVisible
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
