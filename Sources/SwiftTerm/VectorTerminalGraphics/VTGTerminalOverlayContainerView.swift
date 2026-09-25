#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Container view that stacks a terminal view and a transparent VTG overlay.
///
/// Embedding apps still own their terminal subclass, process lifecycle, menus,
/// and window behavior. SwiftTerm owns the reusable layout pattern so VTG hosts
/// do not each need to rediscover the same overlay synchronization code.
open class VTGTerminalOverlayContainerView: VTGPlatformView {
    /// The terminal-like view that receives keyboard focus and renders text.
    public let terminalContentView: VTGPlatformView
    /// Transparent overlay that renders retained VTG scene content.
    public let overlayView: VTGOverlayView
    /// Called when layout or live resize should notify VTG resize subscribers.
    public var resizeNotification: ((_ force: Bool) -> Void)?

    /// The edge constraints that make the terminal fill this container. They
    /// come off while a program has a screen locked, when the terminal is a
    /// centred rectangle instead (VTG `screenLock`).
    private var fillConstraints: [NSLayoutConstraint] = []

    public init(
        frame frameRect: CGRect,
        terminalContentView: VTGPlatformView,
        overlayView: VTGOverlayView = VTGOverlayView(frame: .zero)
    ) {
        self.terminalContentView = terminalContentView
        self.overlayView = overlayView
        super.init(frame: frameRect)
        setup()
    }

    public required init?(coder: NSCoder) {
        self.terminalContentView = VTGPlatformView(frame: .zero)
        self.overlayView = VTGOverlayView(frame: .zero)
        super.init(coder: coder)
        setup()
    }

    /// Shared setup for programmatic and nib/storyboard initialization.
    private func setup() {
        vtgUseTransparentLayer()
        terminalContentView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(terminalContentView)
        addSubview(overlayView)

        fillConstraints = [
            terminalContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalContentView.topAnchor.constraint(equalTo: topAnchor),
            terminalContentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        NSLayoutConstraint.activate(fillConstraints)
    }

    #if os(macOS)
    /// Keep terminal and overlay frames synchronized during layout.
    open override func layout() {
        super.layout()
        layoutContents()
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
    #else
    /// Keep terminal and overlay frames synchronized during layout.
    ///
    /// UIKit has no `setFrameSize` to hook and no live resize to end: a bounds
    /// change arrives here, so this is the one place the notification goes.
    /// A rotation or a Stage Manager resize lands here too.
    open override func layoutSubviews() {
        super.layoutSubviews()
        layoutContents()
    }
    #endif

    /// The layout both platforms perform, wherever their framework calls it.
    ///
    /// Normally the terminal and the overlay fill the container. A program that
    /// locked a screen gets that screen instead: the largest whole multiple of
    /// it that fits, centred, with the rest left as border — scaling a 320×200
    /// screen by anything but a whole number is what makes its pixels
    /// rectangular and its glyphs fringed.
    private func layoutContents() {
        let screen = (terminalContentView as? VectorTerminalView)?.vtgScreenRect(fitting: bounds.size)
        let isLocked = screen != nil
        if fillConstraints.first?.isActive == isLocked {
            NSLayoutConstraint.deactivate(fillConstraints)
            if !isLocked {
                NSLayoutConstraint.activate(fillConstraints)
            }
            terminalContentView.translatesAutoresizingMaskIntoConstraints = isLocked
            overlayView.translatesAutoresizingMaskIntoConstraints = isLocked
        }
        terminalContentView.frame = screen ?? bounds
        overlayView.frame = screen ?? bounds
        overlayView.vtgSetNeedsDisplay()
        resizeNotification?(false)
    }
}

/// Typed variant of `VTGTerminalOverlayContainerView` for embedders that need
/// direct access to their concrete terminal subclass.
open class VTGTypedTerminalOverlayContainerView<TerminalView: VTGPlatformView>: VTGTerminalOverlayContainerView {
    /// Concrete terminal view supplied by the embedding app.
    public let terminalView: TerminalView

    public init(
        frame frameRect: CGRect,
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
