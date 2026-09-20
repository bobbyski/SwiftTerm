#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public extension VTGCanvasSize {
    /// Return the best available VTG canvas size for a terminal embedding.
    ///
    /// The overlay is preferred because it is the actual VTG drawing surface.
    /// When it has not been laid out yet, embedders can fall back through the
    /// terminal's containing view, the terminal view itself, and finally the
    /// window content view.
    static func bestAvailable(
        preferredView: VTGPlatformView?,
        fallbackView: VTGPlatformView
    ) -> VTGCanvasSize {
        if let size = usableSize(for: preferredView) {
            return VTGCanvasSize(size)
        }
        if let size = usableSize(for: fallbackView.superview) {
            return VTGCanvasSize(size)
        }
        if fallbackView.bounds.width > 0 && fallbackView.bounds.height > 0 {
            return VTGCanvasSize(fallbackView.bounds.size)
        }
        #if os(macOS)
        return VTGCanvasSize(fallbackView.window?.contentView?.bounds.size ?? .zero)
        #else
        // A UIWindow is itself the content view; there is no contentView to ask.
        return VTGCanvasSize(fallbackView.window?.bounds.size ?? .zero)
        #endif
    }

    private init(_ size: CGSize) {
        self.init(width: Int(size.width), height: Int(size.height))
    }

    private static func usableSize(for view: VTGPlatformView?) -> CGSize? {
        guard let view else {
            return nil
        }
        view.vtgLayoutIfNeeded()
        guard view.bounds.width > 0, view.bounds.height > 0 else {
            return nil
        }
        return view.bounds.size
    }
}
#endif
