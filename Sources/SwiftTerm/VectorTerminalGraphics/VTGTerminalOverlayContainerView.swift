#if os(macOS)
import AppKit

/// AppKit container that stacks a terminal view and a transparent VTG overlay.
///
/// Embedding apps still own their terminal subclass, process lifecycle, menus,
/// and window behavior. SwiftTerm owns the reusable layout pattern so VTG hosts
/// do not each need to rediscover the same overlay synchronization code.
open class VTGTerminalOverlayContainerView: NSView {
    /// The terminal-like view that receives keyboard focus and renders text.
    public let terminalContentView: NSView
    /// Transparent overlay that renders retained VTG scene content.
    public let overlayView: VTGOverlayView
    /// Called when layout or live resize should notify VTG resize subscribers.
    public var resizeNotification: ((_ force: Bool) -> Void)?

    public init(
        frame frameRect: NSRect,
        terminalContentView: NSView,
        overlayView: VTGOverlayView = VTGOverlayView(frame: .zero)
    ) {
        self.terminalContentView = terminalContentView
        self.overlayView = overlayView
        super.init(frame: frameRect)
        setup()
    }

    public required init?(coder: NSCoder) {
        self.terminalContentView = NSView(frame: .zero)
        self.overlayView = VTGOverlayView(frame: .zero)
        super.init(coder: coder)
        setup()
    }

    /// Shared setup for programmatic and nib/storyboard initialization.
    private func setup() {
        wantsLayer = true
        terminalContentView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(terminalContentView)
        addSubview(overlayView)

        NSLayoutConstraint.activate([
            terminalContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalContentView.topAnchor.constraint(equalTo: topAnchor),
            terminalContentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Keep terminal and overlay frames synchronized during layout.
    open override func layout() {
        super.layout()
        terminalContentView.frame = bounds
        overlayView.frame = bounds
        overlayView.needsDisplay = true
        resizeNotification?(false)
    }

    /// Notify VTG subscribers when the container size changes.
    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resizeNotification?(false)
    }

    /// Force a final resize event after an interactive live resize completes.
    open override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        resizeNotification?(true)
    }
}

/// Typed variant of `VTGTerminalOverlayContainerView` for embedders that need
/// direct access to their concrete terminal subclass.
open class VTGTypedTerminalOverlayContainerView<TerminalView: NSView>: VTGTerminalOverlayContainerView {
    /// Concrete terminal view supplied by the embedding app.
    public let terminalView: TerminalView

    public init(
        frame frameRect: NSRect,
        terminalView: TerminalView,
        overlayView: VTGOverlayView = VTGOverlayView(frame: .zero)
    ) {
        self.terminalView = terminalView
        super.init(
            frame: frameRect,
            terminalContentView: terminalView,
            overlayView: overlayView
        )
    }

    public required init?(coder: NSCoder) {
        fatalError("Use init(frame:terminalView:overlayView:) for VTGTypedTerminalOverlayContainerView")
    }
}
#endif
