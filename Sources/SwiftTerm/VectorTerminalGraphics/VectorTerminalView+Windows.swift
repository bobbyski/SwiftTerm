#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// VTG windows for the terminal view (WINDOW_PLAN.md, experimental).
extension VectorTerminalView {
    /// Feed program output through the window router: plain bytes go to this
    /// terminal, bytes after `windowSelect` go to that window.
    public func feedRoutingVTGWindows(_ bytes: ArraySlice<UInt8>) {
        vtgWindows.feed(bytes) { feed(byteArray: $0) }
    }

    func makeVTGWindowManager() -> VTGWindowManager {
        let manager = VTGWindowManager(
            cellSize: { [weak self] in self?.currentVTGCellSize() ?? (width: 8, height: 16) },
            send: { [weak self] bytes in
                self?.sendVTGResponse(String(decoding: bytes, as: UTF8.self))
            },
            processRunning: { [weak self] in self?.vtgProcessRunningForResponses() ?? false }
        )
        manager.reportsErrors = { [weak self] in self?.vtgSession.controller.sendsErrorEvents ?? false }
        #if os(macOS)
        manager.makeSurface = { [weak self, weak manager] id, columns, rows in
            guard let self else {
                fatalError("VTG window created after its terminal view was released")
            }
            return self.makeVTGWindowSurface(id: id, columns: columns, rows: rows, manager: manager)
        }
        manager.windowsDidChange = { [weak self] in self?.layoutVTGWindows() }
        #endif
        return manager
    }

    #if os(macOS)
    private func makeVTGWindowSurface(id: String, columns: Int, rows: Int,
                                      manager: VTGWindowManager?) -> VTGWindowSurface {
        let frame = manager?.windows[id]?.frame ?? VTGWindowFrame(x: 0, y: 0, columns: columns, rows: rows)
        let container = VTGWindowContainerView(windowID: id, frameModel: frame, owner: self)
        addSubview(container)
        let surface = VTGViewWindowSurface(
            container: container,
            send: { [weak self] bytes in self?.sendVTGResponse(String(decoding: bytes, as: UTF8.self)) },
            sendResponse: { [weak self] response in
                self?.sendVTGResponse(VTGWindowReplyTagger.tag(response, window: id))
            }
        )
        container.terminalView.resize(cols: columns, rows: rows)
        return surface
    }

    /// Place, stack, show and hide each window's view to match the manager.
    func layoutVTGWindows() {
        let cell = currentVTGCellSize() ?? (width: 8, height: 16)
        var desired: [VTGWindowContainerView] = []
        for id in vtgWindows.order {
            guard let window = vtgWindows.windows[id],
                  let surface = window.surface as? VTGViewWindowSurface else {
                continue
            }
            let container = surface.container
            container.frameModel = window.frame
            container.isFocusedWindow = vtgWindows.focusedWindow == id
            container.applyLayout(window.frame.layout(cellWidth: cell.width, cellHeight: cell.height),
                                  in: bounds, rootIsFlipped: isFlipped)
            desired.append(container)
        }
        // Subview order is the stacking order. Restack only when it differs,
        // so ordinary output into a window does not churn the view tree.
        let current = subviews.compactMap { $0 as? VTGWindowContainerView }
        if current.map(ObjectIdentifier.init) != desired.map(ObjectIdentifier.init) {
            for container in desired {
                container.removeFromSuperview()
                addSubview(container)
            }
        }
    }
    #endif
}
#endif
