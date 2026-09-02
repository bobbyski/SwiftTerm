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
    /// Current session-scoped link detection and decoration settings.
    public internal(set) var linkDetectionSettings = VTGLinkDetectionSettings()

    /// Whether the host has stopped answering VTG commands.
    ///
    /// A VTG response is only meaningful to the program that asked for it. Once
    /// that program is gone — it exited, or Ctrl-C killed it before it could
    /// tidy up — anything still on its way lands on whatever owns the terminal
    /// next, which is the user's shell. A shell treats those bytes as typed
    /// input, so a `frameCommitted` acknowledgement ends up spelled out on the
    /// command line:
    ///
    ///     ❯ omegaclideVTG;frameStarted,id=tuikit-chrome,timeout=250
    ///
    /// Muting is how the host is told the conversation is over. It keeps
    /// applying commands — a departing program still wants its `clear` to take
    /// effect — and simply stops replying.
    /// Why the host stopped answering, if it has.
    enum MuteReason {
        /// The program said it was finished, with `detach`. Its word is final:
        /// nothing it sends afterwards starts the conversation again.
        case detached
        /// The host decided the program was gone — it saw the process end, or
        /// the shell back in the foreground. That is a guess about something
        /// the host cannot see directly, so the next command proves it wrong
        /// and lifts it.
        case programGone
    }

    private(set) var muteReason: MuteReason?

    public var isMuted: Bool { muteReason != nil }

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
            // `detach` is the last thing a program says. Handled before the
            // mute check so it works, and before the command is applied so
            // nothing else in this batch can un-say it.
            if command.name == "detach" {
                muteReason = .detached
                discardPendingFrame()
                continue
            }

            // A command arriving is proof a program is there to read the
            // answer, so a guess that one had gone is wrong and is lifted.
            //
            // This matters at startup, which is when the host is most likely
            // to have guessed wrong: `swift run` leaves the shell in the
            // foreground while it builds, and a program that probed for
            // graphics in the moment after that would be told there are none.
            if muteReason == .programGone {
                muteReason = nil
            }
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
        // Commands still applied above: a program on its way out clears its
        // graphics, and that has to land. Only the talking back stops.
        return isMuted ? [] : responses
    }

    /// Stops answering VTG commands, and abandons any frame in flight.
    ///
    /// Called two ways, because a program can leave two ways. A well-behaved
    /// one says so on the way out — that is the `detach` command. One killed by
    /// a signal says nothing at all, so the embedding view mutes on its behalf
    /// when it notices the program is gone.
    ///
    /// The pending frame goes too: its acknowledgement is exactly the reply
    /// that would otherwise be typed into the shell.
    public func mute() {
        // Never downgrades an explicit goodbye to a guess.
        if muteReason == nil {
            muteReason = .programGone
        }
        discardPendingFrame()
    }

    /// Resumes answering. Called when a new program takes the terminal.
    public func unmute() {
        muteReason = nil
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
