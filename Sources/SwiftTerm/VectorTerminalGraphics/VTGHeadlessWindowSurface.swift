import Foundation

/// A window surface with no view: a terminal and a VTG session, wired together.
///
/// ```text
///   routed bytes ──▶ Terminal ──APC──▶ VTGHostSession ──▶ scene, replies
///                       │                                     │
///                       └── terminal replies (DA, DSR) ──┐    │ tagged window=<id>
///                                                        ▼    ▼
///                                                   VTGWindowManager.send
/// ```
///
/// The GL hosts draw it with the same renderers they use for the root, and
/// tests drive it without a GPU. Everything a terminal or a VTG program can do
/// works inside it, because it is the same `Terminal` and the same
/// `VTGHostSession` the root uses — only smaller, and fed by the router.
public final class VTGHeadlessWindowSurface: VTGWindowSurface {
    public let terminal: Terminal
    public var session: VTGHostSession { sessionStorage }
    /// Set once in `init`; implicitly unwrapped only because the session's
    /// callbacks need `self` before `init` finishes.
    private var sessionStorage: VTGHostSession!

    private let delegate: Delegate
    private let cellSize: () -> (width: Double, height: Double)

    /// - Parameters:
    ///   - columns: Grid width in cells.
    ///   - rows: Grid height in cells.
    ///   - scrollback: Lines kept above the grid. Windows keep few (WINDOW_PLAN.md 3.8).
    ///   - cellSize: The host's cell, in canvas points; a window's canvas is
    ///     its grid times this.
    ///   - send: Where terminal replies go (the program's input).
    ///   - sendResponse: Where VTG replies go, already tagged with the window.
    ///   - processRunning: Whether the program can still read replies.
    ///   - sceneDidChange: Told when the window's scene changes, to redraw.
    public init(columns: Int,
                rows: Int,
                scrollback: Int = 200,
                cellSize: @escaping () -> (width: Double, height: Double),
                send: @escaping ([UInt8]) -> Void,
                sendResponse: @escaping (String) -> Void,
                processRunning: @escaping () -> Bool,
                sceneDidChange: @escaping () -> Void) {
        self.cellSize = cellSize
        delegate = Delegate(send: send)
        terminal = Terminal(delegate: delegate,
                            options: TerminalOptions(cols: max(1, columns), rows: max(1, rows), scrollback: scrollback))
        let terminal = self.terminal
        sessionStorage = VTGHostSession(
            canvasProvider: {
                let cell = cellSize()
                return VTGCanvasSize(width: Int((Double(terminal.cols) * cell.width).rounded()),
                                     height: Int((Double(terminal.rows) * cell.height).rounded()))
            },
            glyphSizeProvider: { cellSize() },
            processRunning: processRunning,
            sendResponse: sendResponse,
            sceneDidChange: { _ in sceneDidChange() }
        )
        terminal.registerPrivateSequenceHandler { [weak self] sequence in
            self?.session.handlePrivateSequence(sequence) ?? false
        }
    }

    public func feed(_ bytes: ArraySlice<UInt8>) {
        terminal.feed(buffer: bytes)
    }

    public func resize(columns: Int, rows: Int) {
        terminal.resize(cols: max(1, columns), rows: max(1, rows))
        // The window's program learns its new canvas the way any VTG program
        // does: a `resize` event, if it subscribed.
        session.notifyResizeIfNeeded()
    }

    public func close() {
        session.discardPendingFrame()
    }

    /// Terminal callbacks for a window: replies go to the program; everything
    /// that would change the host window (title, size) is ignored, because a
    /// VTG window is not the host's window.
    private final class Delegate: TerminalDelegate {
        let send: ([UInt8]) -> Void

        init(send: @escaping ([UInt8]) -> Void) {
            self.send = send
        }

        func showCursor(source: Terminal) {}
        func hideCursor(source: Terminal) {}
        func setTerminalTitle(source: Terminal, title: String) {}
        func setTerminalIconTitle(source: Terminal, title: String) {}
        func windowCommand(source: Terminal, command: Terminal.WindowManipulationCommand) -> [UInt8]? { nil }
        func sizeChanged(source: Terminal) {}
        func scrolled(source: Terminal, yDisp: Int) {}
        func linefeed(source: Terminal) {}
        func bufferActivated(source: Terminal) {}
        func bell(source: Terminal) {}
        func send(source: Terminal, data: ArraySlice<UInt8>) {
            send(Array(data))
        }
    }
}
