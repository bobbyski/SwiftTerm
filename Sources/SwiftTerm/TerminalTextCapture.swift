import Foundation

/// A cursor bookmark for extracting ordinary command output without its echo.
/// Bookmarks are invalid across terminal resize, screen changes, or eviction.
public struct TerminalTextBookmark {
    fileprivate let buffer: ObjectIdentifier
    fileprivate let row: Int
    fileprivate let column: Int
    fileprivate let columns: Int
}

public extension Terminal {
    /// Records the current output position after the shell's command-start mark.
    func markTextPosition() -> TerminalTextBookmark {
        TerminalTextBookmark(buffer: ObjectIdentifier(buffer), row: buffer.linesTop + buffer.yBase + buffer.y,
                             column: buffer.x, columns: cols)
    }

    /// Extracts ordinary text up to the current cursor. This is a snapshot of
    /// retained cells, not a lossless transcript of full-screen cursor editing.
    func text(since bookmark: TerminalTextBookmark) throws -> String {
        let (start, end) = try rangeForTextCapture(since: bookmark)
        return getText(start: start, end: end)
    }

    // Shared validation for plain and styled snapshots of the same bookmark.
    internal func rangeForTextCapture(since bookmark: TerminalTextBookmark) throws -> (Position, Position) {
        guard bookmark.buffer == ObjectIdentifier(buffer), bookmark.columns == cols else {
            throw TextCaptureError.screenChanged
        }
        let row = bookmark.row - buffer.linesTop
        let end = Position(col: buffer.x, row: buffer.yBase + buffer.y)
        let start = Position(col: bookmark.column, row: row)
        guard row >= 0, row < buffer.lines.count else { throw TextCaptureError.historyEvicted }
        guard Position.compare(start, end) != .after else { throw TextCaptureError.cursorMovedBeforeStart }
        return (start, end)
    }

    /// A text snapshot cannot be reconstructed honestly from the retained cells.
    enum TextCaptureError: Error {
        case screenChanged
        case historyEvicted
        case cursorMovedBeforeStart
    }
}
