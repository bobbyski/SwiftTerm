import Foundation

/// Told where a terminal writes, for drawing that must give way to text:
/// VTG raster mode with `text=erases` (WINDOW_PLAN.md Phase 5).
///
/// ```text
///   print "A" at row 3, col 7      →  cellsWritten(row: 3, columns: 7..<8)
///   erase to end of line           →  cellsWritten(row: y, columns: x..<cols)
///   line feed at the bottom        →  rowsScrolled(top: 0, bottom: rows - 1, count: 1)
///   reset, resize, alt screen      →  screenInvalidated()
/// ```
///
/// Rows are visible rows, 0 at the top of the screen. Nothing is reported while
/// no observer is set, which is always, unless a program asked for it: each
/// call site is one nil check.
public protocol TerminalCellWriteObserver: AnyObject {
    /// Cells `columns` of visible row `row` were written or erased, whatever
    /// they held before — a space written over a space counts.
    func cellsWritten(row: Int, columns: Range<Int>)
    /// Rows `top...bottom` moved up by `count` lines, or down when `count` is
    /// negative; the rows uncovered are blank.
    func rowsScrolled(top: Int, bottom: Int, count: Int)
    /// Everything on screen may have changed: a reset, a resize, a switch
    /// between the main and alternate screens.
    func screenInvalidated()
}
