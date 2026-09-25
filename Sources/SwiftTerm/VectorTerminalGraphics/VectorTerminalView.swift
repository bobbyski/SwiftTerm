#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// VTG-capable variant of `TerminalView` for host-fed terminal content.
///
/// `VectorTerminalView` is intended for embedders that already own the program
/// or interpreter producing terminal bytes. Unlike `LocalProcessTerminalView`,
/// it does not launch or manage a child process. The host feeds normal terminal
/// text and VTG APC sequences through `feed(byteArray:)`, `feed(text:)`, or
/// `feedVTG(_:)`; the view renders terminal text with SwiftTerm's existing
/// renderer and VTG graphics in a transparent overlay.
///
/// Plain `TerminalView` remains unchanged. Apps opt into VTG only by creating
/// this subclass.
open class VectorTerminalView: TerminalView {
    /// Transparent retained-graphics overlay drawn above the terminal text.
    public let vtgOverlayView = VTGOverlayView(frame: .zero)

    /// The visible VTG Page Mode page, composited above the overlay.
    public let vtgPageView = VTGPageView(frame: .zero)
    private var vtgPageStacking: VTGPageStacking = .all

    #if os(iOS)
    /// Turns taps and drags into VTG mouse events. The Mac does this in
    /// `LocalProcessVectorTerminalView`; iOS has no process view to do it in.
    private var vtgTouchInput: VTGTouchInput?
    #endif

    /// The font this view had before a program locked the screen, put back
    /// when the screen is unlocked.
    var vtgFontBeforeScreenLock: VTGPlatformFont?

    /// The cell a locked screen pins, or nil for a normal terminal whose cell
    /// comes from its font. Read by `computeFontDimensions()`.
    var vtgLockedCellDimension: CGSize?

    /// Told when a program locks or unlocks the screen.
    ///
    /// A host that lays this view out itself re-centres it here, giving the
    /// view ``vtgScreenRect(fitting:)`` of the space it has (see
    /// `VectorTerminalView+ScreenLock.swift`).
    public var onScreenLockChange: ((VTGScreenLock?) -> Void)?

    /// Optional response sink for VTG queries and host-generated events.
    ///
    /// Local-process terminals send VTG responses back to the child process.
    /// Host-fed views do not have a process, so embedders can use this closure
    /// when their in-process app needs to consume `capabilities?`, `canvas?`,
    /// `resize`, or mouse responses.
    public var vtgResponseHandler: ((String) -> Void)?

    /// Whether the view has stopped answering VTG commands.
    public var vectorGraphicsResponsesMuted: Bool {
        vtgSession.controller.isMuted
    }

    /// Clears retained graphics and protocol subscriptions for a guest reboot.
    public func resetVectorGraphicsSession() {
        vtgSession.resetSession()
    }

    /// Stops answering VTG commands, and drops any frame left open.
    ///
    /// For the case a departing program cannot handle itself. One that exits
    /// cleanly sends `detach`; one killed by Ctrl-C sends nothing, and its
    /// unread acknowledgements are then delivered to whatever owns the
    /// terminal next — the shell — which types them out:
    ///
    ///     ❯ omegaclideVTG;frameStarted,id=tuikit-chrome,timeout=250
    ///
    /// An embedder that can tell when the foreground program has gone should
    /// call this then, and ``resumeVectorGraphicsResponses()`` when a new one
    /// takes over.
    public func muteVectorGraphicsResponses() {
        vtgSession.mute()
    }

    /// Resumes answering VTG commands, for the next program.
    public func resumeVectorGraphicsResponses() {
        vtgSession.unmute()
    }

    internal lazy var vtgSession = VTGHostSession(
        canvasProvider: { [weak self] in
            guard let self else {
                return VTGCanvasSize(width: 0, height: 0)
            }
            return self.currentVTGCanvas()
        },
        rendererProvider: { [weak self] in
            self?.currentVTGRendererName() ?? "overlay"
        },
        glyphSizeProvider: { [weak self] in
            guard let self else {
                return nil
            }
            return self.currentVTGCellSize()
        },
        processRunning: { [weak self] in
            self?.vtgProcessRunningForResponses() == true
        },
        sendResponse: { [weak self] response in
            self?.sendVTGResponse(response)
        },
        sceneDidChange: { [weak self] scene in
            guard let self else {
                return
            }
            self.vtgOverlayView.scene = scene
            self.vtgOverlayView.isHidden = !self.areGraphicsLayersVisible
            self.vtgOverlayView.vtgSetNeedsDisplay()
            self.refreshVTGPageView()
            self.vtgSetNeedsDisplay()
        },
        linkDetectionDidChange: { [weak self] settings in
            self?.applyVTGLinkDetectionSettings(settings)
        }
    )

    private var vtgHostIsActive = true

    private func applyVTGLinkDetectionSettings(_ settings: VTGLinkDetectionSettings) {
        linkReporting = settings.isEnabled ? .implicit : .none
        linkDecorationEnabled = settings.decoratesLinks
        linkDecorationColor = settings.color
    }

    public override init(frame: CGRect, font: VTGPlatformFont?) {
        super.init(frame: frame, font: font)
        setupVectorTerminalView()
    }

    public override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        setupVectorTerminalView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupVectorTerminalView()
    }

    /// Feed VTG bytes from an in-process SDK transport.
    ///
    /// This is intentionally just a convenience wrapper over SwiftTerm's normal
    /// byte feed. Host-fed applications should send VTG through the same parser
    /// path as process-backed applications so the wire protocol stays honest.
    public func feedVTG(_ data: Data) {
        feed(byteArray: Array(data)[...])
    }

    /// Feed VTG bytes from an in-process SDK transport.
    public func feedVTG(_ bytes: [UInt8]) {
        feed(byteArray: bytes[...])
    }

    /// Renderer name advertised through `VTG;capabilities?`.
    ///
    /// The value is intentionally a small string instead of exposing
    /// SwiftTerm's renderer enum on the wire. Existing clients already parse
    /// flat capability fields, and unknown renderer strings should be treated
    /// as informational.
    public func currentVTGRendererName() -> String {
        switch rendererMode {
        case .coreGraphics:
            return "coreGraphics"
        case .metal:
            return "metal"
        case .svg:
            return "svg"
        }
    }

    /// Temporarily disable host-generated VTG responses.
    ///
    /// Drawing commands still render when fed to the view. This only gates
    /// events and query responses for hosts that do not want an active response
    /// channel.
    public func setVTGHostActive(_ isActive: Bool) {
        vtgHostIsActive = isActive
        if !isActive {
            vtgSession.discardPendingFrame()
        }
    }

    /// Whether all retained VTG graphics layers are currently rendered.
    public var areGraphicsLayersVisible: Bool {
        vtgSession.graphicsLayersVisible
    }

    /// Show or hide all VTG graphics layers while preserving retained state.
    public func setGraphicsLayersVisible(_ isVisible: Bool) {
        vtgSession.setGraphicsLayersVisible(isVisible)
        vtgOverlayView.isHidden = !isVisible
        vtgOverlayView.vtgSetNeedsDisplay()
        refreshVTGPageView()
        vtgSetNeedsDisplay()
    }

    /// Whether a program currently has VTG Page Mode active.
    public var isVectorGraphicsPageModeActive: Bool {
        vtgSession.pageMode != nil
    }

    /// End VTG Page Mode on the user's behalf — the escape hatch for a page
    /// left over the terminal. The program, if it is still running, is told
    /// with `pageEnded,reason=host`.
    public func dismissVectorGraphicsPage() {
        vtgSession.endPageMode(reason: "host")
    }

    /// Show the visible page, if any, at the stacking the program asked for.
    func refreshVTGPageView() {
        let mode = vtgSession.pageMode
        let page = mode?.visiblePage
        vtgPageView.page = page
        vtgPageView.isHidden = page == nil || !areGraphicsLayersVisible
        if let stacking = mode?.stacking, stacking != vtgPageStacking {
            vtgPageStacking = stacking
            vtgPageView.removeFromSuperview()
            if stacking == .text {
                vtgAddSubview(vtgPageView, below: vtgOverlayView)
            } else {
                vtgAddSubview(vtgPageView, above: vtgOverlayView)
            }
            pinToEdges(vtgPageView)
        }
        vtgPageView.vtgSetNeedsDisplay()
    }

    private func pinToEdges(_ view: VTGPlatformView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Toggle all VTG graphics layers and return the new visibility state.
    @discardableResult
    public func toggleGraphicsLayersVisible() -> Bool {
        let nextValue = !areGraphicsLayersVisible
        setGraphicsLayersVisible(nextValue)
        return nextValue
    }

    /// Send a resize event to any host-fed subscriber when the canvas changes.
    public func notifyVTGResizeIfNeeded(force: Bool = false) {
        vtgSession.notifyResizeIfNeeded(force: force)
    }

    /// The canvas coordinates events are reported in: the locked screen's
    /// pixels when one is locked, the view's own size otherwise.
    ///
    /// A click three-quarters across a locked 320-pixel screen is x=240,
    /// whatever the window is; that is what the program drew in.
    func vtgEventCanvas(viewWidth: Double, viewHeight: Double) -> (width: Double, height: Double) {
        guard let lock = vtgScreenLock else {
            return (width: viewWidth, height: viewHeight)
        }
        return (width: Double(lock.width), height: Double(lock.height))
    }

    /// Current VTG canvas size used by VTG queries and event coordinates.
    open func currentVTGCanvas() -> VTGCanvasSize {
        VTGCanvasSize.bestAvailable(
            preferredView: vtgOverlayView,
            fallbackView: self
        )
    }

    /// Current terminal cell size in VTG logical canvas coordinates.
    ///
    /// `cellSizeInPixels(...)` reports backing pixels on Retina displays, but
    /// VTG drawing commands use the logical canvas coordinate space. Query
    /// responses must use the same coordinate system as drawing or cell-aligned
    /// graphics will be misplaced by the backing scale factor.
    open func currentVTGCellSize() -> (width: Double, height: Double)? {
        // `cellDimension` is implicitly unwrapped on macOS and non-optional on
        // iOS, so it is coerced to an optional to keep one nil-safe guard.
        guard let cell = cellDimension as CellDimension?, cell.width > 0, cell.height > 0 else {
            return nil
        }
        return (
            width: max(1, Double(cell.width)),
            height: max(1, Double(cell.height))
        )
    }

    /// Re-places text-anchored layers for the current scroll position.
    ///
    /// Called on every scroll and before drawing, because both the buffer
    /// moving under the view (output) and the view moving over the buffer
    /// (scrollback) change where an anchored line sits.
    ///
    /// Uses ``currentVTGCellSize()`` rather than `cellDimension` directly so
    /// the offset lands in the same logical space VTG draws in — on a Retina
    /// display the two differ by the backing scale, and mixing them would
    /// misplace every anchored layer by that factor.
    open func updateTextAnchoredGraphics() {
        guard let cell = currentVTGCellSize() else {
            return
        }
        vtgSession.controller.scene.updateTextAnchoredLayers(
            topLine: getTerminal().buffer.yDisp,
            cellHeight: cell.height
        )
    }

    /// The absolute buffer line the cursor is on, which is what an anchor
    /// without an explicit `line=` means: "pin this to where I am now".
    open func currentAbsoluteLine() -> Int {
        let buffer = getTerminal().buffer
        return buffer.yBase + buffer.y
    }

    /// Whether VTG responses/events should be emitted.
    ///
    /// Host-fed views use a simple active flag. Process-backed subclasses
    /// override this to track child-process liveness.
    open func vtgProcessRunningForResponses() -> Bool {
        vtgHostIsActive
    }

    /// Deliver a VTG response to the embedding host.
    ///
    /// Host-fed views call `vtgResponseHandler`; process-backed subclasses
    /// override this to write back into the pseudo-terminal.
    open func sendVTGResponse(_ response: String) {
        vtgResponseHandler?(response)
    }

    #if os(macOS)
    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // A locked screen's cell follows the view's size.
        applyVTGScreenLock()
        vtgOverlayView.frame = bounds
        vtgPageView.frame = bounds
        notifyVTGResizeIfNeeded()
    }

    open override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutVTGViews()
        notifyVTGResizeIfNeeded()
    }

    open override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        notifyVTGResizeIfNeeded(force: true)
    }
    #else
    /// Keep the overlay and the page over the terminal as it lays out.
    ///
    /// UIKit sends every size change here — rotation, a split-view divider
    /// dragged, a keyboard appearing — and there is no separate end-of-resize
    /// moment to force a final event from.
    open override func layoutSubviews() {
        super.layoutSubviews()
        layoutVTGViews()
        notifyVTGResizeIfNeeded()
    }
    #endif

    /// Resize the VTG views onto the terminal's bounds and redraw them.
    private func layoutVTGViews() {
        // A locked screen's cell follows the view's size, so it is recomputed
        // before the overlay and page are told to redraw.
        applyVTGScreenLock()
        vtgOverlayView.frame = bounds
        vtgOverlayView.vtgSetNeedsDisplay()
        vtgPageView.frame = bounds
        vtgPageView.vtgSetNeedsDisplay()
    }

    /// Draw committed VTG layer 0 primitives during SwiftTerm's CoreGraphics
    /// terminal pass.
    ///
    /// Metal bypasses this CoreGraphics hook. Its renderer has a narrow native
    /// layer-0 spike for the vector subset that already works in the Metal VTG
    /// primitive pipeline, while richer layer-0 behavior remains reserved.
    open override func drawTerminalTextPlaneGraphics(dirtyRect: CGRect, context: CGContext) {
        guard areGraphicsLayersVisible else {
            return
        }
        let scene = vtgSession.visibleSceneSnapshot
        guard !scene.textPlanePrimitives.isEmpty else {
            return
        }
        // Layer 0 draws in the same locked pixels the overlay does.
        vtgOverlayView.drawLocked(in: context, bounds: bounds) { canvasBounds in
            vtgOverlayView.draw(scene: scene, plane: .textPlane, in: context, bounds: canvasBounds)
        }
    }

    private func setupVectorTerminalView() {
        vtgOverlayView.translatesAutoresizingMaskIntoConstraints = false
        vtgAddSubview(vtgOverlayView, above: nil)
        NSLayoutConstraint.activate([
            vtgOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            vtgOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            vtgOverlayView.topAnchor.constraint(equalTo: topAnchor),
            vtgOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        vtgPageView.translatesAutoresizingMaskIntoConstraints = false
        vtgAddSubview(vtgPageView, above: vtgOverlayView)
        pinToEdges(vtgPageView)
        vtgPageView.isHidden = true

        #if os(iOS)
        vtgTouchInput = VTGTouchInput(view: self)
        #endif

        vtgSession.screenLockDidChange = { [weak self] lock in
            guard let self else { return }
            self.applyVTGScreenLock()
            self.onScreenLockChange?(lock)
        }

        terminal.registerPrivateSequenceHandler { [weak self] sequence in
            self?.vtgSession.handlePrivateSequence(sequence) ?? false
        }
        // A shell prompt mark means the program that opened a page has gone —
        // the one signal that also works when that program ran over SSH.
        terminal.semanticPromptObserver = { [weak self] kind in
            guard kind == UInt8(ascii: "A") || kind == UInt8(ascii: "D") else {
                return
            }
            self?.vtgSession.endPageMode(reason: "promptMark")
        }
        terminal.fullResetObserver = { [weak self] in
            self?.vtgSession.endPageMode(reason: "reset")
        }
        vtgOverlayView.isHidden = !areGraphicsLayersVisible
    }
}
#endif
