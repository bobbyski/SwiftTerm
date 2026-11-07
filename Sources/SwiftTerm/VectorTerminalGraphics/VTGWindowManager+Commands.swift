import Foundation

/// The window commands (WINDOW_PLAN.md Phase 2).
///
/// | Command | Parameters |
/// |---|---|
/// | `windowCreate` | `id`, `cols`, `rows`, `x`, `y`, `title`, `border=0\|1`, `shadow=0\|1` |
/// | `windowClose` | `id` |
/// | `windowSelect` | `id=<w>\|root` — where output goes next |
/// | `windowMove` | `id`, `x`, `y` |
/// | `windowResize` | `id`, `cols`, `rows` |
/// | `windowRaise` / `windowLower` | `id` |
/// | `windowOrder` | `ids=a\|b\|c` — these to the top, `c` topmost |
/// | `windowFocus` | `id=<w>\|root` |
/// | `windowHide` / `windowShow` | `id` |
/// | `windows?` | — answered with `windows,order=…,focus=…,selected=…,max=…` |
/// | `windowEvents` | `enabled=1` — report clicks on window frames as `windowMouse` |
///
/// A refused command is answered with `windowRejected,command=,id=,reason=`
/// only when the program turned on `errorEvents`, as sprite refusals are.
extension VTGWindowManager {
    func handle(_ command: VectorTerminalGraphicsCommand) {
        switch command.name {
        case "windowCreate":
            create(command)
        case "windowClose":
            withWindow(command) { close($0.id) }
        case "windowSelect":
            select(command)
        case "windowMove":
            withWindow(command) { window in
                window.frame.x = command.double("x", default: window.frame.x)
                window.frame.y = command.double("y", default: window.frame.y)
            }
        case "windowResize":
            resize(command)
        case "windowRaise":
            withWindow(command) { window in
                order.removeAll { $0 == window.id }
                order.append(window.id)
            }
        case "windowLower":
            withWindow(command) { window in
                order.removeAll { $0 == window.id }
                order.insert(window.id, at: 0)
            }
        case "windowOrder":
            reorder(command)
        case "windowFocus":
            focus(command)
        case "windowHide":
            withWindow(command) { $0.frame.isHidden = true }
        case "windowShow":
            withWindow(command) { $0.frame.isHidden = false }
        case "windowEvents":
            reportsFrameEvents = ["1", "true", "yes", "on"].contains((command.parameters["enabled"] ?? "0").lowercased())
        case "windows?":
            sendVTG("windows", [("order", order.joined(separator: "|")),
                                ("focus", focusedWindow ?? "root"),
                                ("selected", selectedWindow ?? "root"),
                                ("max", String(Self.maximumWindows))])
        default:
            break
        }
    }

    private func withWindow(_ command: VectorTerminalGraphicsCommand, _ body: (VTGWindow) -> Void) {
        guard let id = command.parameters["id"], let window = windows[id] else {
            reject(command, reason: "unknownWindow")
            return
        }
        body(window)
    }

    private func create(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"], VTGGraphicsScene.isValidIdentifier(id), id != "root" else {
            reject(command, reason: "badId")
            return
        }
        guard windows[id] == nil else {
            reject(command, reason: "exists")
            return
        }
        guard windows.count < Self.maximumWindows else {
            reject(command, reason: "limit")
            return
        }
        let columns = Int(command.double("cols", default: 0))
        let rows = Int(command.double("rows", default: 0))
        let range = 1...VTGWindowFrame.maximumCells
        guard range.contains(columns), range.contains(rows) else {
            reject(command, reason: "badSize")
            return
        }
        let frame = VTGWindowFrame(
            x: command.double("x", default: 0),
            y: command.double("y", default: 0),
            columns: columns,
            rows: rows,
            title: command.parameters["title"] ?? "",
            hasBorder: command.parameters["border"] != "0",
            hasShadow: command.parameters["shadow"] != "0"
        )
        windows[id] = VTGWindow(id: id, frame: frame,
                                surface: makeWindowSurface(id: id, columns: columns, rows: rows))
        order.append(id)
    }

    func close(_ id: String) {
        guard let window = windows.removeValue(forKey: id) else {
            return
        }
        window.surface.close()
        order.removeAll { $0 == id }
        if focusedWindow == id {
            focusedWindow = nil
        }
        if router.selectedWindow == id {
            router.select(nil)
        }
    }

    /// The router has already switched; a window that does not exist sends
    /// output back to the root rather than nowhere.
    private func select(_ command: VectorTerminalGraphicsCommand) {
        guard let id = router.selectedWindow else {
            return
        }
        if windows[id] == nil {
            router.select(nil)
            reject(command, reason: "unknownWindow")
        }
    }

    private func resize(_ command: VectorTerminalGraphicsCommand) {
        withWindow(command) { window in
            let columns = Int(command.double("cols", default: Double(window.frame.columns)))
            let rows = Int(command.double("rows", default: Double(window.frame.rows)))
            let range = 1...VTGWindowFrame.maximumCells
            guard range.contains(columns), range.contains(rows) else {
                reject(command, reason: "badSize")
                return
            }
            window.frame.columns = columns
            window.frame.rows = rows
            window.surface.resize(columns: columns, rows: rows)
        }
    }

    private func reorder(_ command: VectorTerminalGraphicsCommand) {
        let ids = (command.parameters["ids"] ?? "").split(separator: "|").map(String.init)
        guard !ids.isEmpty, ids.allSatisfy({ windows[$0] != nil }), Set(ids).count == ids.count else {
            reject(command, reason: "unknownWindow")
            return
        }
        order.removeAll { ids.contains($0) }
        order.append(contentsOf: ids)
    }

    private func focus(_ command: VectorTerminalGraphicsCommand) {
        let id = command.parameters["id"]
        if id == nil || id == "root" {
            focusedWindow = nil
            return
        }
        guard let id, windows[id] != nil else {
            reject(command, reason: "unknownWindow")
            return
        }
        focusedWindow = id
    }
}
