#if os(macOS)
import AppKit

extension LocalProcessVectorTerminalView {
    func updateVTGScrollEventMonitor() {
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
            if self.handleVTGPageScroll(event) {
                return nil
            }
            return self.sendVTGScrollEventToChild(event) ? nil : event
        }
    }

    /// Scroll a visible VTG page, when its program enabled user scrolling.
    func handleVTGPageScroll(_ event: NSEvent) -> Bool {
        guard vtgSession.pageMode?.userScrollEnabled == true else {
            return false
        }
        let point = convert(event.locationInWindow, from: nil)
        let lineHeight = Double(cellDimension?.height ?? 16)
        let deltaX = event.hasPreciseScrollingDeltas ? Double(event.scrollingDeltaX) : Double(event.deltaX) * lineHeight
        let deltaY = event.hasPreciseScrollingDeltas ? Double(event.scrollingDeltaY) : Double(event.deltaY) * lineHeight
        return vtgSession.handlePageUserScroll(
            at: VTGPoint(x: Double(point.x), y: Double(bounds.height - point.y)),
            deltaX: deltaX,
            deltaY: deltaY
        )
    }

    func handleVTGMouseDown(_ event: NSEvent) -> Bool {
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

    func handleVTGMouseUp(_ event: NSEvent) -> Bool {
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

    func sendVTGMouseEventToChild(_ event: NSEvent, type: VTGMouseEventType) -> Bool {
        guard let snapshot = vtgMouseSnapshot(for: event) else {
            return false
        }
        return vtgSession.sendMouseEvent(
            type: type,
            button: event.buttonNumber,
            snapshot: snapshot
        )
    }

    func sendVTGScrollEventToChild(_ event: NSEvent) -> Bool {
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
        // A locked screen reports in its own pixels, so the fraction across
        // the view is scaled into the screen rather than into the window.
        let canvas = vtgEventCanvas(viewWidth: Double(bounds.width), viewHeight: Double(bounds.height))
        let scaleX = bounds.width > 0 ? canvas.width / Double(bounds.width) : 1
        let scaleY = bounds.height > 0 ? canvas.height / Double(bounds.height) : 1
        let mapper = VTGMouseCoordinateMapper(
            columns: terminal.cols,
            rows: terminal.rows,
            canvasWidth: canvas.width,
            canvasHeight: canvas.height
        )
        guard let position = mapper.cellPosition(
            pixelX: Double(point.x) * scaleX,
            pixelY: Double(bounds.height - point.y) * scaleY
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
