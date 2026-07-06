#if os(macOS)
import AppKit
import Foundation

/// VTG-capable local-process terminal view.
///
/// `LocalProcessVectorTerminalView` is the process-backed companion to
/// ``VectorTerminalView``. It launches a local child process in a pseudo-terminal
/// exactly like `LocalProcessTerminalView`, but routes received bytes through the
/// VTG-aware parser and renders VTG graphics on the overlay supplied by
/// ``VectorTerminalView``.
///
/// The original `LocalProcessTerminalView` remains untouched; applications opt
/// into VTG by replacing their view type with this class.
open class LocalProcessVectorTerminalView: VectorTerminalView, TerminalViewDelegate, LocalProcessDelegate {
    /// The local pseudo-terminal process connected to this view.
    public internal(set) var process: LocalProcess!

    /// Delegate used to report process and terminal metadata changes.
    public weak var processDelegate: LocalProcessVectorTerminalViewDelegate?

    let vtgClickSynthesizer = VTGMouseClickSynthesizer()
    var scrollEventMonitor: Any?

    public override init(frame: CGRect, font: NSFont?) {
        super.init(frame: frame, font: font)
        setupLocalProcessVectorTerminalView()
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLocalProcessVectorTerminalView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLocalProcessVectorTerminalView()
    }

    private func setupLocalProcessVectorTerminalView() {
        terminalDelegate = self
        process = LocalProcess(delegate: self)
    }

    deinit {
        if let scrollEventMonitor {
            NSEvent.removeMonitor(scrollEventMonitor)
        }
    }

    open override func mouseDown(with event: NSEvent) {
        if handleVTGMouseDown(event) {
            return
        }
        super.mouseDown(with: event)
    }

    open override func rightMouseDown(with event: NSEvent) {
        if handleVTGMouseDown(event) {
            return
        }
        super.rightMouseDown(with: event)
    }

    open override func otherMouseDown(with event: NSEvent) {
        if handleVTGMouseDown(event) {
            return
        }
        super.otherMouseDown(with: event)
    }

    open override func mouseUp(with event: NSEvent) {
        if handleVTGMouseUp(event) {
            return
        }
        super.mouseUp(with: event)
    }

    open override func rightMouseUp(with event: NSEvent) {
        if handleVTGMouseUp(event) {
            return
        }
        super.rightMouseUp(with: event)
    }

    open override func otherMouseUp(with event: NSEvent) {
        if handleVTGMouseUp(event) {
            return
        }
        super.otherMouseUp(with: event)
    }

    open override func mouseDragged(with event: NSEvent) {
        if sendVTGMouseEventToChild(event, type: .drag) {
            return
        }
        super.mouseDragged(with: event)
    }

    open override func rightMouseDragged(with event: NSEvent) {
        if sendVTGMouseEventToChild(event, type: .drag) {
            return
        }
        super.rightMouseDragged(with: event)
    }

    open override func otherMouseDragged(with event: NSEvent) {
        if sendVTGMouseEventToChild(event, type: .drag) {
            return
        }
        super.otherMouseDragged(with: event)
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateVTGScrollEventMonitor()
    }

    /// Send user input to the child process.
    open func send(source: TerminalView, data: ArraySlice<UInt8>) {
        process.send(data: data)
    }

    /// Update the pseudo-terminal size after the SwiftTerm grid changes.
    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard process.running else {
            return
        }

        var size = getWindowSize()
        let _ = PseudoTerminalHelpers.setWinSize(
            masterPtyDescriptor: process.childfd,
            windowSize: &size
        )

        processDelegate?.sizeChanged(source: self, newCols: newCols, newRows: newRows)
        notifyVTGResizeIfNeeded()
    }

    /// Copy terminal selection content to the macOS pasteboard.
    public func clipboardCopy(source: TerminalView, content: Data) {
        if let str = String(bytes: content, encoding: .utf8) {
            let pasteBoard = NSPasteboard.general
            pasteBoard.clearContents()
            pasteBoard.writeObjects([str as NSString])
        }
    }

    /// Read UTF-8 pasteboard content for terminal paste requests.
    public func clipboardRead(source: TerminalView) -> Data? {
        guard let str = NSPasteboard.general.string(forType: .string) else {
            return nil
        }
        return str.data(using: .utf8)
    }

    /// Forward title changes requested by the child process.
    public func setTerminalTitle(source: TerminalView, title: String) {
        processDelegate?.setTerminalTitle(source: self, title: title)
    }

    /// Forward OSC 7 directory changes requested by the child process.
    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        processDelegate?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }

    /// Required terminal delegate hook; scrolling is handled by SwiftTerm.
    open func scrolled(source: TerminalView, position: Double) {}

    /// Required terminal delegate hook for changed render ranges.
    open func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    /// Forward terminal bell events to the embedding app.
    open func bell(source: TerminalView) {
        processDelegate?.bell(source: source)
    }

    /// Called by ``LocalProcess`` when the child process exits.
    open func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        vtgSession.discardPendingFrame()
        processDelegate?.processTerminated(source: self, exitCode: exitCode)
    }

    /// Feed child process output through the VTG-aware terminal parser.
    open func dataReceived(slice: ArraySlice<UInt8>) {
        feed(byteArray: slice)
    }

    /// Process-backed VTG responses are written back to the child process.
    open override func sendVTGResponse(_ response: String) {
        process.send(data: Array(response.utf8)[...])
    }

    /// Process-backed VTG events are only emitted while the child is alive.
    open override func vtgProcessRunningForResponses() -> Bool {
        process?.running == true
    }

    /// Return the pseudo-terminal size in cells and approximate pixels.
    open func getWindowSize() -> winsize {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let pxW = Int((cellDimension?.width ?? 0) * CGFloat(terminal.cols) * scale)
        let pxH = Int((cellDimension?.height ?? 0) * CGFloat(terminal.rows) * scale)
        return winsize(
            ws_row: UInt16(terminal.rows),
            ws_col: UInt16(terminal.cols),
            ws_xpixel: UInt16(pxW),
            ws_ypixel: UInt16(pxH)
        )
    }

}
#endif
