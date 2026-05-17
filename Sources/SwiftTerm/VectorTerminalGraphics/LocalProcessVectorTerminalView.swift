#if os(macOS)
import AppKit
import Foundation

/// Delegate for ``LocalProcessVectorTerminalView`` process lifecycle events.
///
/// This mirrors `LocalProcessTerminalViewDelegate` while using
/// `LocalProcessVectorTerminalView` as the source type. Keeping it separate lets
/// existing SwiftTerm users keep their current delegates unchanged, while VTG
/// adopters get strong typing for the new drop-in view.
public protocol LocalProcessVectorTerminalViewDelegate: AnyObject {
    /// Called after the terminal grid changes size and the pseudo-terminal size
    /// has been updated for the child process.
    func sizeChanged(source: LocalProcessVectorTerminalView, newCols: Int, newRows: Int)

    /// Called when the child process requests a terminal title change.
    func setTerminalTitle(source: LocalProcessVectorTerminalView, title: String)

    /// Called when OSC 7 reports a new host current directory.
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?)

    /// Called when the child process exits.
    func processTerminated(source: TerminalView, exitCode: Int32?)
}

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

    private let vtgClickSynthesizer = VTGMouseClickSynthesizer()
    private var scrollEventMonitor: Any?

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

    /// Launch a child process inside a pseudo-terminal.
    public func startProcess(
        executable: String = "/bin/bash",
        args: [String] = [],
        environment: [String]? = nil,
        execName: String? = nil,
        currentDirectory: String? = nil
    ) {
        process.startProcess(
            executable: executable,
            args: args,
            environment: environment,
            execName: execName,
            currentDirectory: currentDirectory
        )
    }

    /// Terminate the child process.
    public func terminate() {
        process.terminate()
    }

    /// Enable or disable host IO logging for the child process.
    public func setHostLogging(directory: String?) {
        process.setHostLogging(directory: directory)
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

    /// Forward terminal bell events to the standard SwiftTerm behavior.
    open func bell(source: TerminalView) {}

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

    open override func mouseDown(with event: NSEvent) {
        if handleVTGMouseDown(event) {
            return
        }
        super.mouseDown(with: event)
    }

    open override func mouseUp(with event: NSEvent) {
        if handleVTGMouseUp(event) {
            return
        }
        super.mouseUp(with: event)
    }

    open override func mouseDragged(with event: NSEvent) {
        if sendVTGMouseEventToChild(event, type: .drag) {
            return
        }
        super.mouseDragged(with: event)
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateVTGScrollEventMonitor()
    }

    private func writeSVGSnapshot(_ svg: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "VectorTerminal-\(formatter.string(from: Date())).svg"
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        let fileURL = directory.appendingPathComponent(fileName)
        try svg.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func updateVTGScrollEventMonitor() {
        if let scrollEventMonitor {
            NSEvent.removeMonitor(scrollEventMonitor)
            self.scrollEventMonitor = nil
        }
        guard window != nil else {
            return
        }
        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else {
                return event
            }
            return self.sendVTGScrollEventToChild(event) ? nil : event
        }
    }

    private func handleVTGMouseDown(_ event: NSEvent) -> Bool {
        guard vtgSession.sendsMouseEvents else {
            return false
        }
        if let snapshot = vtgMouseSnapshot(for: event) {
            vtgClickSynthesizer.recordDown(
                button: event.buttonNumber,
                snapshot: snapshot,
                timestamp: event.timestamp
            )
        }
        if vtgSession.mouseMode.emitsRawMouse {
            return sendVTGMouseEventToChild(event, type: .down)
        }
        return true
    }

    private func handleVTGMouseUp(_ event: NSEvent) -> Bool {
        guard vtgSession.sendsMouseEvents else {
            return false
        }
        var handled = false
        if vtgSession.mouseMode.emitsRawMouse {
            handled = sendVTGMouseEventToChild(event, type: .up)
        }
        if shouldSynthesizeClick(for: event),
           sendVTGMouseEventToChild(event, type: .click) {
            handled = true
        }
        vtgClickSynthesizer.reset()
        return handled || vtgSession.mouseMode == .click
    }

    private func shouldSynthesizeClick(for event: NSEvent) -> Bool {
        guard let snapshot = vtgMouseSnapshot(for: event) else {
            return false
        }
        return vtgClickSynthesizer.shouldSynthesizeClick(
            button: event.buttonNumber,
            snapshot: snapshot,
            timestamp: event.timestamp
        )
    }

    private func sendVTGMouseEventToChild(_ event: NSEvent, type: VTGMouseEventType) -> Bool {
        guard let snapshot = vtgMouseSnapshot(for: event) else {
            return false
        }
        return vtgSession.sendMouseEvent(
            type: type,
            button: event.buttonNumber,
            snapshot: snapshot
        )
    }

    private func sendVTGScrollEventToChild(_ event: NSEvent) -> Bool {
        guard vtgSession.sendsMouseEvents,
              vtgSession.mouseMode.emitsScroll,
              let snapshot = vtgMouseSnapshot(for: event) else {
            return false
        }
        let scrollX = Int((event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX).rounded())
        let scrollY = Int((event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY).rounded())
        let button = scrollY > 0 ? 4 : scrollY < 0 ? 5 : 6
        return vtgSession.sendMouseEvent(
            type: .scroll,
            button: button,
            snapshot: snapshot,
            scrollX: scrollX,
            scrollY: scrollY
        )
    }

    private func vtgMouseSnapshot(for event: NSEvent) -> VTGMouseSnapshot? {
        let point = convert(event.locationInWindow, from: nil)
        let mapper = VTGMouseCoordinateMapper(
            columns: terminal.cols,
            rows: terminal.rows,
            canvasWidth: Double(bounds.width),
            canvasHeight: Double(bounds.height)
        )
        guard let position = mapper.cellPosition(
            pixelX: Double(point.x),
            pixelY: Double(bounds.height - point.y)
        ) else {
            return nil
        }
        return VTGMouseSnapshot(
            x: position.pixelX,
            y: position.pixelY,
            cellX: position.gridCol + 1,
            cellY: position.gridRow + 1,
            modifiers: event.modifierFlags.vtgMouseModifiers
        )
    }
}
#endif
