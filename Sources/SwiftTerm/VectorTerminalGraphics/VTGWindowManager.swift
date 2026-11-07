import Foundation

/// One VTG window: its frame, and the surface that runs and draws it.
public final class VTGWindow {
    public let id: String
    public internal(set) var frame: VTGWindowFrame
    public let surface: VTGWindowSurface

    init(id: String, frame: VTGWindowFrame, surface: VTGWindowSurface) {
        self.id = id
        self.frame = frame
        self.surface = surface
    }
}

/// VTG windows (WINDOW_PLAN.md, experimental): small VTG programs, each with
/// its own text grid and graphics layers, stacked in an order the program sets.
///
/// ```text
///   root terminal (always at the bottom, exactly as today)
///   ┌──────────────────────────────────────────────┐
///   │      order[0] ┌──────────┐                   │
///   │               │  ┌───────┴──────┐ order[1]   │   later in `order` = on top
///   │               └──│              │            │
///   │                  └──────────────┘            │
///   └──────────────────────────────────────────────┘
/// ```
///
/// The host feeds every byte from the program through `feed(_:root:)` instead
/// of straight into its terminal. Until the program creates a window, that
/// call hands the bytes straight back to the root (see `VTGWindowRouter`), so
/// a program that never uses windows sees no difference at all.
///
/// The manager is headless: it owns stacking, focus, routing and the window
/// commands, and leaves drawing to the host's compositor, which reads
/// `visibleWindows` bottom to top.
public final class VTGWindowManager {
    /// How many windows a program may have at once, advertised as `windowMax`.
    public static let maximumWindows = 16

    /// Windows by id.
    public internal(set) var windows: [String: VTGWindow] = [:]
    /// Stacking order, bottom to top.
    public internal(set) var order: [String] = []
    /// The window whose cursor is shown and whose events are reported first,
    /// or nil for the root.
    public internal(set) var focusedWindow: String?

    let router = VTGWindowRouter()

    /// The host's cell, in root canvas points.
    public var cellSize: () -> (width: Double, height: Double)
    /// Makes the surface for a new window. Defaults to a headless one.
    public var makeSurface: ((String, Int, Int) -> VTGWindowSurface)?
    /// Bytes for the program: replies, tagged or raw.
    public var send: ([UInt8]) -> Void
    /// Whether the program can still read replies.
    public var processRunning: () -> Bool
    /// Whether the program asked to hear about clicks on window frames
    /// (`windowEvents,enabled=1`), which it needs to drag or raise windows.
    public internal(set) var reportsFrameEvents = false
    /// Whether the program asked for refusals (`errorEvents`) on the root.
    public var reportsErrors: () -> Bool = { false }
    /// Told whenever anything about the windows changed, so the host redraws.
    public var windowsDidChange: () -> Void = {}

    public init(cellSize: @escaping () -> (width: Double, height: Double),
                send: @escaping ([UInt8]) -> Void,
                processRunning: @escaping () -> Bool) {
        self.cellSize = cellSize
        self.send = send
        self.processRunning = processRunning
    }

    /// Whether any window exists.
    public var hasWindows: Bool {
        !windows.isEmpty
    }

    /// The window output currently goes to, or nil for the root.
    public var selectedWindow: String? {
        router.selectedWindow
    }

    /// Visible windows, bottom to top: the order a compositor draws them in.
    public var visibleWindows: [VTGWindow] {
        order.compactMap { windows[$0] }.filter { !$0.frame.isHidden }
    }

    // MARK: - Feeding

    /// Route one read from the program.
    ///
    /// - Parameter root: Feeds bytes to the root terminal. Called with the
    ///   caller's own slice, uncopied, when the read holds no window command
    ///   and no window is selected.
    public func feed(_ bytes: ArraySlice<UInt8>, root: (ArraySlice<UInt8>) -> Void) {
        if router.passesStraightThrough(bytes) {
            root(bytes)
            return
        }
        var changed = false
        for segment in router.route(bytes) {
            switch segment {
            case .bytes(let slice, let target):
                if let target, let window = windows[target] {
                    window.surface.feed(slice)
                    changed = true
                } else {
                    root(slice)
                }
            case .command(let command):
                handle(command)
                changed = true
            }
        }
        if changed {
            windowsDidChange()
        }
    }

    /// Close every window and send output to the root again: for a terminal
    /// reset, or a new program taking the terminal, so a program that died
    /// mid-select cannot leave output going to a window.
    public func reset() {
        let hadWindows = hasWindows || router.selectedWindow != nil
        for window in windows.values {
            window.surface.close()
        }
        windows.removeAll()
        order.removeAll()
        focusedWindow = nil
        reportsFrameEvents = false
        router.reset()
        if hadWindows {
            windowsDidChange()
        }
    }

    // MARK: - Hit testing

    /// The topmost visible window under a root canvas point, and where in its
    /// content the point falls (nil when it is on the border or title bar).
    public func window(at point: VTGPoint) -> (window: VTGWindow, contentPoint: VTGPoint?)? {
        let cell = cellSize()
        for window in visibleWindows.reversed() {
            let layout = window.frame.layout(cellWidth: cell.width, cellHeight: cell.height)
            guard Self.contains(layout.outer, point) else {
                continue
            }
            let content = layout.content
            let local = Self.contains(content, point)
                ? VTGPoint(x: point.x - content.x, y: point.y - content.y)
                : nil
            return (window, local)
        }
        return nil
    }

    static func contains(_ rect: VTGLayerClip, _ point: VTGPoint) -> Bool {
        point.x >= rect.x && point.y >= rect.y && point.x < rect.x + rect.width && point.y < rect.y + rect.height
    }

    // MARK: - Replies

    func sendVTG(_ name: String, _ fields: [(String, String)]) {
        guard processRunning() else {
            return
        }
        send(Array(VTGResponseEncoder.apc(name, fields).utf8))
    }

    func reject(_ command: VectorTerminalGraphicsCommand, reason: String) {
        print("VTG window: \(command.name) refused (\(reason)) id=\(command.parameters["id"] ?? "")")
        guard reportsErrors() else {
            return
        }
        sendVTG("windowRejected", [("command", command.name),
                                   ("id", command.parameters["id"] ?? ""),
                                   ("reason", reason)])
    }

    func makeWindowSurface(id: String, columns: Int, rows: Int) -> VTGWindowSurface {
        if let makeSurface {
            return makeSurface(id, columns, rows)
        }
        return VTGHeadlessWindowSurface(
            columns: columns,
            rows: rows,
            cellSize: { [weak self] in self?.cellSize() ?? (width: 8, height: 16) },
            send: { [weak self] bytes in
                guard let self, self.processRunning() else { return }
                self.send(bytes)
            },
            sendResponse: { [weak self] response in
                guard let self, self.processRunning() else { return }
                self.send(Array(VTGWindowReplyTagger.tag(response, window: id).utf8))
            },
            processRunning: { [weak self] in self?.processRunning() ?? false },
            sceneDidChange: { [weak self] in self?.windowsDidChange() }
        )
    }
}
