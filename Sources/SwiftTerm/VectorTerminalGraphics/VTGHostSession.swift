import Foundation

/// Reusable host-side VTG session glue for terminal embedding views.
///
/// `VTGHostController` owns protocol state and wire encoding. `VTGHostSession`
/// connects that controller to the platform/application boundary: current
/// canvas size, process liveness, response writing, and overlay invalidation.
/// Embedding views still own native events and process lifecycle.
public final class VTGHostSession {
    public let controller: VTGHostController

    public var canvasProvider: () -> VTGCanvasSize
    public var rendererProvider: () -> String
    public var processRunning: () -> Bool
    public var sendResponse: (String) -> Void
    public var sceneDidChange: (VTGGraphicsScene) -> Void

    public init(
        controller: VTGHostController = VTGHostController(),
        canvasProvider: @escaping () -> VTGCanvasSize,
        rendererProvider: @escaping () -> String = { "overlay" },
        processRunning: @escaping () -> Bool,
        sendResponse: @escaping (String) -> Void,
        sceneDidChange: @escaping (VTGGraphicsScene) -> Void
    ) {
        self.controller = controller
        self.canvasProvider = canvasProvider
        self.rendererProvider = rendererProvider
        self.processRunning = processRunning
        self.sendResponse = sendResponse
        self.sceneDidChange = sceneDidChange
    }

    /// Whether the child process has subscribed to VTG mouse events.
    public var sendsMouseEvents: Bool {
        controller.sendsMouseEvents
    }

    /// Current VTG mouse mode requested by the child process.
    public var mouseMode: VTGMouseMode {
        controller.mouseMode
    }

    /// Whether retained VTG graphics layers are currently rendered.
    public var graphicsLayersVisible: Bool {
        controller.graphicsLayersVisible
    }

    /// Snapshot of the currently visible retained VTG scene.
    ///
    /// This is intended for embedders and future terminal-renderer integration
    /// that need to inspect scene state without mutating the controller-owned
    /// visible scene. Pending offscreen frames are intentionally excluded until
    /// they are committed through `endFrame`.
    public var visibleSceneSnapshot: VTGGraphicsScene {
        controller.scene.makeSnapshot()
    }

    /// Return currently visible primitives for one compositing plane.
    ///
    /// This small read API keeps renderer spikes from reaching into the
    /// controller's scene internals. Layer -1 maps to `.underText`, layer 0
    /// maps to `.textPlane`, and overlay layers map to `.overlay`.
    public func visiblePrimitives(in plane: VTGCompositingPlane) -> [VTGPrimitive] {
        controller.scene.renderPrimitives(in: plane)
    }

    /// Process a SwiftTerm private sequence and send any immediate responses.
    @discardableResult
    public func handlePrivateSequence(_ sequence: TerminalPrivateSequence) -> Bool {
        guard let responses = controller.handlePrivateSequence(
            sequence,
            canvas: canvasProvider(),
            renderer: rendererProvider()
        ) else {
            return false
        }
        responses.forEach(sendResponse)
        sceneDidChange(controller.scene)
        return true
    }

    /// Send a resize event when the child subscribed and the canvas changed.
    public func notifyResizeIfNeeded(force: Bool = false) {
        guard let response = controller.resizeResponseIfNeeded(
            canvas: canvasProvider(),
            force: force,
            processRunning: processRunning()
        ) else {
            return
        }
        sendResponse(response)
    }

    /// Discard any pending graphics-only frame.
    ///
    /// This gives embedders an explicit recovery hook for process teardown and
    /// host-side resets. It intentionally does not clear the visible VTG scene;
    /// it only drops work that had not yet been committed with `endFrame`.
    public func discardPendingFrame() {
        controller.discardPendingFrame()
        sceneDidChange(controller.scene)
    }

    /// Show or hide all VTG graphics layers without clearing retained objects.
    public func setGraphicsLayersVisible(_ isVisible: Bool) {
        controller.setGraphicsLayersVisible(isVisible)
        sceneDidChange(controller.scene)
    }

    /// Send a VTG mouse event if the current mouse mode accepts it.
    @discardableResult
    public func sendMouseEvent(
        type: VTGMouseEventType,
        button: Int,
        snapshot: VTGMouseSnapshot,
        scrollX: Int? = nil,
        scrollY: Int? = nil
    ) -> Bool {
        guard processRunning(),
              let response = controller.mouseResponse(
                  type: type,
                  button: button,
                  snapshot: snapshot,
                  canvas: canvasProvider(),
                  scrollX: scrollX,
                  scrollY: scrollY
              ) else {
            return false
        }
        sendResponse(response)
        return true
    }
}
