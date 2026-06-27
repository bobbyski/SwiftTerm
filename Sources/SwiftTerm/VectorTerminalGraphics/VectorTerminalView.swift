#if os(macOS)
import AppKit

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

    /// Optional response sink for VTG queries and host-generated events.
    ///
    /// Local-process terminals send VTG responses back to the child process.
    /// Host-fed views do not have a process, so embedders can use this closure
    /// when their in-process app needs to consume `capabilities?`, `canvas?`,
    /// `resize`, or mouse responses.
    public var vtgResponseHandler: ((String) -> Void)?

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
            self.vtgOverlayView.needsDisplay = true
            self.needsDisplay = true
        }
    )

    private var vtgHostIsActive = true

    public override init(frame: CGRect, font: NSFont?) {
        super.init(frame: frame, font: font)
        setupVectorTerminalView()
    }

    public override init(frame frameRect: NSRect) {
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
        vtgOverlayView.needsDisplay = true
        needsDisplay = true
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

    /// Current VTG canvas size used by VTG queries and event coordinates.
    open func currentVTGCanvas() -> VTGCanvasSize {
        VTGCanvasSize.bestAvailable(
            preferredView: vtgOverlayView,
            fallbackView: self
        )
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

    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        vtgOverlayView.frame = bounds
        notifyVTGResizeIfNeeded()
    }

    open override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        vtgOverlayView.frame = bounds
        vtgOverlayView.needsDisplay = true
        notifyVTGResizeIfNeeded()
    }

    open override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        notifyVTGResizeIfNeeded(force: true)
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
        vtgOverlayView.draw(scene: scene, plane: .textPlane, in: context, bounds: bounds)
    }

    private func setupVectorTerminalView() {
        vtgOverlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vtgOverlayView, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            vtgOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            vtgOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            vtgOverlayView.topAnchor.constraint(equalTo: topAnchor),
            vtgOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        terminal.registerPrivateSequenceHandler { [weak self] sequence in
            self?.vtgSession.handlePrivateSequence(sequence) ?? false
        }
        vtgOverlayView.isHidden = !areGraphicsLayersVisible
    }
}
#endif
