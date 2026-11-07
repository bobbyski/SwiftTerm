#if os(macOS)
import AppKit

/// A VTG window on the Mac (WINDOW_PLAN.md 4.1): a frame view holding a child
/// `VectorTerminalView`, which runs the window's own terminal and VTG session.
///
/// ```text
///   root VectorTerminalView
///   ├── vtgOverlayView           (root layers 1…4)
///   ├── vtgPageView
///   ├── VTGWindowContainerView   order[0]  ┐  subview order = window order,
///   └── VTGWindowContainerView   order[1]  ┘  so AppKit does the stacking
///         └── VectorTerminalView (child: grid, layers, sprites, cursor)
/// ```
///
/// The child is a full terminal view, so both Mac renderers, CoreGraphics and
/// Metal, draw windows exactly as they draw the root. The container draws only
/// the frame — shadow, border and title bar — and takes the pointer, which it
/// hands to the window manager in root canvas points.
final class VTGWindowContainerView: NSView {
    let windowID: String
    let terminalView: VectorTerminalView
    weak var owner: VectorTerminalView?
    var frameModel: VTGWindowFrame
    var isFocusedWindow = false {
        didSet {
            if isFocusedWindow != oldValue { needsDisplay = true }
            // Only the focused window shows a cursor: CoreGraphics draws it as
            // a caret view, Metal draws it itself.
            terminalView.vtgCursorSuppressed = !isFocusedWindow
            if terminalView.rendererMode == .metal {
                terminalView.requestMetalDisplay()
            } else {
                terminalView.caretView?.isHidden = !isFocusedWindow
            }
        }
    }

    static let borderColor = NSColor(calibratedRed: 0.55, green: 0.6, blue: 0.68, alpha: 1)
    static let focusedBorderColor = NSColor(calibratedRed: 0.38, green: 0.65, blue: 0.98, alpha: 1)
    static let titleBarColor = NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.24, alpha: 1)
    static let titleTextColor = NSColor(calibratedRed: 0.9, green: 0.92, blue: 0.95, alpha: 1)

    init(windowID: String, frameModel: VTGWindowFrame, owner: VectorTerminalView) {
        self.windowID = windowID
        self.frameModel = frameModel
        self.owner = owner
        terminalView = VectorTerminalView(frame: .zero, font: owner.font)
        super.init(frame: .zero)
        // A window's own session never advertises windows: they do not nest.
        terminalView.vtgSession.controller.advertisesWindows = false
        terminalView.nativeForegroundColor = owner.nativeForegroundColor
        terminalView.nativeBackgroundColor = owner.nativeBackgroundColor
        if owner.rendererMode == .metal {
            try? terminalView.setUseMetal(true)
        }
        addSubview(terminalView)
        // No window has focus until the program gives it one.
        terminalView.vtgCursorSuppressed = true
        if terminalView.rendererMode != .metal {
            terminalView.caretView?.isHidden = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("VTGWindowContainerView is created in code")
    }

    override var isFlipped: Bool { true }

    /// Lay the container and its terminal out from the window's frame.
    func applyLayout(_ layout: VTGWindowLayout, in rootBounds: CGRect, rootIsFlipped: Bool) {
        let outer = layout.outer
        let y = rootIsFlipped ? outer.y : Double(rootBounds.height) - outer.y - outer.height
        frame = CGRect(x: outer.x, y: y, width: outer.width, height: outer.height)
        terminalView.frame = CGRect(x: layout.content.x - outer.x, y: layout.content.y - outer.y,
                                    width: layout.content.width, height: layout.content.height)
        // A terminal view sizes its grid from its frame, less its scroller;
        // the window's grid is what the program asked for, so set it back.
        let terminal = terminalView.getTerminal()
        if terminal.cols != frameModel.columns || terminal.rows != frameModel.rows {
            terminalView.resize(cols: frameModel.columns, rows: frameModel.rows)
        }
        // A shadow needs a layer; a window without one stays an ordinary view.
        if frameModel.hasShadow {
            wantsLayer = true
            layer?.masksToBounds = false
            layer?.shadowOpacity = 0.35
            layer?.shadowOffset = CGSize(width: 4, height: -4)
            layer?.shadowRadius = 2
        }
        isHidden = frameModel.isHidden
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let owner else {
            return
        }
        if frameModel.hasBorder {
            context.setFillColor((isFocusedWindow ? Self.focusedBorderColor : Self.borderColor).cgColor)
            context.fill(bounds)
        }
        let cell = owner.currentVTGCellSize() ?? (width: 8, height: 16)
        if let bar = frameModel.layout(cellWidth: cell.width, cellHeight: cell.height).titleBar {
            let barRect = CGRect(x: bar.x - frameModel.x, y: bar.y - frameModel.y, width: bar.width, height: bar.height)
            context.setFillColor(Self.titleBarColor.cgColor)
            context.fill(barRect)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(8, bar.height * 0.7)),
                .foregroundColor: Self.titleTextColor,
            ]
            (frameModel.title as NSString).draw(at: CGPoint(x: barRect.minX + 4, y: barRect.minY + bar.height * 0.1),
                                                 withAttributes: attributes)
        }
    }

    // MARK: - Pointer

    /// The window takes every pointer event inside it, so nothing reaches
    /// the root through it — a window hides what is below it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // AppKit passes the point in the superview's coordinates.
        guard !isHidden else { return nil }
        return frame.contains(point) ? self : nil
    }

    private func forward(_ type: VTGMouseEventType, _ event: NSEvent, button: Int) {
        guard let owner else { return }
        let local = owner.convert(event.locationInWindow, from: nil)
        let y = owner.isFlipped ? local.y : owner.bounds.height - local.y
        owner.vtgWindows.handleMouse(type: type, button: button,
                                     at: VTGPoint(x: Double(local.x), y: Double(y)),
                                     modifiers: VTGWindowContainerView.modifiers(event))
    }

    static func modifiers(_ event: NSEvent) -> String {
        var modifiers: VTGMouseModifiers = []
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.alt) }
        return modifiers.wireValue
    }

    override func mouseDown(with event: NSEvent) { forward(.down, event, button: 0) }
    override func mouseUp(with event: NSEvent) {
        forward(.up, event, button: 0)
        forward(.click, event, button: 0)
    }
    override func mouseDragged(with event: NSEvent) { forward(.drag, event, button: 0) }
    override func rightMouseDown(with event: NSEvent) { forward(.down, event, button: 2) }
    override func rightMouseUp(with event: NSEvent) { forward(.up, event, button: 2) }
}

/// The Mac's `VTGWindowSurface`: the child terminal view inside a container.
final class VTGViewWindowSurface: VTGWindowSurface {
    let container: VTGWindowContainerView
    private let forwarder: Forwarder

    init(container: VTGWindowContainerView, send: @escaping ([UInt8]) -> Void,
         sendResponse: @escaping (String) -> Void) {
        self.container = container
        forwarder = Forwarder(send: send)
        container.terminalView.terminalDelegate = forwarder
        container.terminalView.vtgResponseHandler = sendResponse
    }

    var terminal: Terminal { container.terminalView.getTerminal() }
    var session: VTGHostSession { container.terminalView.vtgSession }

    func feed(_ bytes: ArraySlice<UInt8>) {
        container.terminalView.feed(byteArray: bytes)
    }

    func resize(columns: Int, rows: Int) {
        container.terminalView.resize(cols: columns, rows: rows)
        session.notifyResizeIfNeeded()
    }

    func close() {
        container.removeFromSuperview()
    }

    /// Terminal-view callbacks for a window: what the window's terminal says
    /// back (device reports, typed keys) goes to the program's one input.
    private final class Forwarder: TerminalViewDelegate {
        let send: ([UInt8]) -> Void
        init(send: @escaping ([UInt8]) -> Void) { self.send = send }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func send(source: TerminalView, data: ArraySlice<UInt8>) { send(Array(data)) }
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
#endif
