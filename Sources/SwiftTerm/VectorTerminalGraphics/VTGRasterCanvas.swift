import Foundation

/// One change to a raster framebuffer, in the order it happened.
public enum VTGRasterOperation: Equatable {
    /// Paint a primitive, in canvas points, over what is there.
    case draw(VTGPrimitive)
    /// Text was written here: erase the drawing in these cells.
    case eraseCells(row: Int, columns: Range<Int>)
    /// Rows `top...bottom` moved up by `count` (down when negative), as the
    /// text did; the rows uncovered are empty.
    case scroll(top: Int, bottom: Int, count: Int)
    /// Erase everything.
    case clear
}

/// Raster mode with `text=erases` (WINDOW_PLAN.md Phase 5): a framebuffer the
/// text can overwrite.
///
/// ```text
///   guest: rasterMode,enabled=1,text=erases
///
///   drawing commands ──▶ .draw ─┐
///   text written     ──▶ .eraseCells ─┼──▶ operations ──▶ host's raster surface
///   text scrolled    ──▶ .scroll ─┘       (drained each frame, in order)
/// ```
///
/// Nothing is retained here: the canvas is a queue of what changed since the
/// host's renderer last looked, and the renderer keeps the pixels. So a program
/// that plots every frame costs the pixels it plots, not an ever-longer list
/// (Finding B). And because a write is reported whatever the cell held — a
/// space over a space counts — a window of blank text erases what was under it,
/// which no rule that only looks at the screen can do (WINDOW_PLAN.md option R).
///
/// The canvas is the terminal's `cellWriteObserver` only while this mode is
/// on; otherwise the terminal reports nothing at all.
public final class VTGRasterCanvas: TerminalCellWriteObserver {
    /// Changes not yet applied by the host's renderer, oldest first.
    public private(set) var operations: [VTGRasterOperation] = []

    /// Told whenever an operation is queued, so the host redraws.
    public var didChange: () -> Void = {}

    /// Operations kept for a renderer that is not draining them — a hidden
    /// view, say. Past this the oldest are dropped, with a message, rather
    /// than growing without limit.
    public static let maximumQueuedOperations = 200_000

    public init() {}

    /// Take every queued operation, in order, for the renderer to apply.
    public func takeOperations() -> [VTGRasterOperation] {
        defer { operations.removeAll(keepingCapacity: true) }
        return operations
    }

    /// Queue a drawing.
    public func draw(_ primitive: VTGPrimitive) {
        append(.draw(primitive))
    }

    /// Erase everything: queued drawing included, since a clear wipes it anyway.
    public func clear() {
        operations.removeAll(keepingCapacity: true)
        append(.clear)
    }

    private func append(_ operation: VTGRasterOperation) {
        if operations.count >= Self.maximumQueuedOperations {
            print("VTGRasterCanvas: \(operations.count) operations not drawn; dropping the oldest half")
            operations.removeFirst(operations.count / 2)
        }
        operations.append(operation)
        didChange()
    }

    // MARK: - TerminalCellWriteObserver

    public func cellsWritten(row: Int, columns: Range<Int>) {
        guard !columns.isEmpty else {
            return
        }
        // Printing reports one run at a time; join runs on the same row.
        if case .eraseCells(let lastRow, let lastColumns)? = operations.last,
           lastRow == row, lastColumns.upperBound == columns.lowerBound {
            operations[operations.count - 1] = .eraseCells(row: row, columns: lastColumns.lowerBound..<columns.upperBound)
            return
        }
        append(.eraseCells(row: row, columns: columns))
    }

    public func rowsScrolled(top: Int, bottom: Int, count: Int) {
        append(.scroll(top: top, bottom: bottom, count: count))
    }

    public func screenInvalidated() {
        clear()
    }
}
