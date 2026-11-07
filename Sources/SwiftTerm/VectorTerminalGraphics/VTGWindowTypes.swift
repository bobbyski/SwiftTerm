import Foundation

/// Where a VTG window sits and how it is dressed.
///
/// Position is in root canvas points, so a window can be dragged smoothly;
/// size is in cells, because a window holds a terminal grid.
///
/// ```text
///   (x, y)
///     ┌─────────── title ───────────┐   ← title bar, one cell high (when titled)
///     │ content: columns × rows     │   ← the window's own terminal and VTG scene
///     │ cells                       │
///     └─────────────────────────────┘   ← border, `borderWidth` points (when bordered)
/// ```
public struct VTGWindowFrame: Equatable {
    public var x: Double
    public var y: Double
    public var columns: Int
    public var rows: Int
    public var title: String
    public var hasBorder: Bool
    public var hasShadow: Bool
    public var isHidden: Bool

    /// Border thickness, in points, when the window has a border.
    public static let borderWidth = 1.0

    /// The largest grid a window may ask for, either way.
    public static let maximumCells = 500

    public init(x: Double, y: Double, columns: Int, rows: Int,
                title: String = "", hasBorder: Bool = true, hasShadow: Bool = true, isHidden: Bool = false) {
        self.x = x
        self.y = y
        self.columns = columns
        self.rows = rows
        self.title = title
        self.hasBorder = hasBorder
        self.hasShadow = hasShadow
        self.isHidden = isHidden
    }

    /// The window's rectangles for a given cell size.
    public func layout(cellWidth: Double, cellHeight: Double) -> VTGWindowLayout {
        let border = hasBorder ? Self.borderWidth : 0
        let titleHeight = title.isEmpty ? 0 : cellHeight
        let content = VTGLayerClip(x: x + border, y: y + border + titleHeight,
                                   width: Double(columns) * cellWidth, height: Double(rows) * cellHeight)
        let outer = VTGLayerClip(x: x, y: y,
                                 width: content.width + 2 * border,
                                 height: content.height + titleHeight + 2 * border)
        let titleBar = titleHeight > 0
            ? VTGLayerClip(x: x + border, y: y + border, width: content.width, height: titleHeight)
            : nil
        return VTGWindowLayout(outer: outer, content: content, titleBar: titleBar)
    }
}

/// A window's rectangles, in root canvas points.
public struct VTGWindowLayout: Equatable {
    /// Everything the window covers: border, title bar and content.
    public var outer: VTGLayerClip
    /// The window's terminal grid.
    public var content: VTGLayerClip
    /// The title bar, when the window has a title.
    public var titleBar: VTGLayerClip?
}

/// What draws and runs one window: a terminal grid with its own VTG session.
///
/// The headless surface (`VTGHeadlessWindowSurface`) serves the GL hosts and
/// tests. A platform may supply its own — the Mac uses a child terminal view —
/// as long as the window manager can feed it bytes and resize it.
public protocol VTGWindowSurface: AnyObject {
    /// The window's own terminal.
    var terminal: Terminal { get }
    /// The window's own VTG session: scene, layers, sprites, events.
    var session: VTGHostSession { get }
    /// Feed bytes routed to this window.
    func feed(_ bytes: ArraySlice<UInt8>)
    /// Change the grid to `columns` × `rows` cells.
    func resize(columns: Int, rows: Int)
    /// The window is closing; release anything the platform holds.
    func close()
}

/// Marks replies that come from a window with `window=<id>`.
///
/// `ESC _ VTG;mouse,x=3,y=4 ESC \` from window `map` becomes
/// `ESC _ VTG;mouse,window=map,x=3,y=4 ESC \`. The field goes first, so a
/// reader that splits on commas finds it without knowing the reply.
public enum VTGWindowReplyTagger {
    public static func tag(_ response: String, window id: String) -> String {
        let prefix = "\u{1B}_VTG;"
        guard response.hasPrefix(prefix) else {
            return response
        }
        let body = response.dropFirst(prefix.count)
        guard let nameEnd = body.firstIndex(where: { $0 == "," || $0 == "\u{1B}" || $0 == ";" }) else {
            return response
        }
        // Whatever follows the name — more fields, a payload, or the
        // terminator — follows the new field unchanged.
        return prefix + body[..<nameEnd] + ",window=" + id + body[nameEnd...]
    }
}
