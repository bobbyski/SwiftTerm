import Foundation

/// Decides whether a terminal cell holds ink: something visible that a layer
/// asking for `layerOcclude,by=ink` must not be drawn over.
///
/// A cell has ink when any of these is true:
///
/// - it holds a visible character (anything above a space, unless it is
///   marked invisible);
/// - its background is not the terminal's default;
/// - it is drawn inverse, which paints the foreground color behind it;
/// - it is underlined or crossed out, which draws a line even through a space.
///
/// A blank cell in the default colors has no ink, even if a program wrote a
/// space there on purpose — the rule sees what the screen shows, not how it got
/// there. That is the known limit of this rule (WINDOW_PLAN.md): a window filled
/// with default-background spaces lets graphics show through its interior.
/// Blinking is ignored, so a mask does not flicker with the blink phase.
public enum VTGCellInkRule {
    /// Whether `cell` holds ink.
    public static func hasInk(_ cell: CharData) -> Bool {
        let attribute = cell.attribute
        let style = attribute.style
        if style.contains(.inverse) || style.contains(.underline) || style.contains(.crossedOut) {
            return true
        }
        if attribute.underlineStyle != .none {
            return true
        }
        if !isDefaultBackground(attribute.bg) {
            return true
        }
        if style.contains(.invisible) {
            return false
        }
        // Grapheme clusters live outside the simple rune range and are always
        // visible text.
        guard cell.isSimpleRune else {
            return true
        }
        return cell.code > 0x20
    }

    /// Both spellings the engine uses for "the terminal's own background".
    private static func isDefaultBackground(_ color: Attribute.Color) -> Bool {
        switch color {
        case .defaultColor, .defaultInvertedColor:
            return true
        default:
            return false
        }
    }
}

/// Builds the text mask for the visible screen: one rectangle per run of
/// inked cells, in VTG canvas points.
///
/// ```text
///   row 2   . . │ █ █ █ █ │ . . .     →   [col 2…8]           one hole
///   row 3   . . │ . . . . │ . X .     →   [col 2] [col 7] [col 9]
/// ```
///
/// Rows are cached by line identity and `BufferLine.generation`, so a frame in
/// which nothing changed reuses every row, and a frame in which one line
/// changed rescans only that line. The builder is cheap to keep alive per view
/// and never retains a line.
public final class VTGTextOcclusionMaskBuilder {
    private struct CachedRow {
        var lineID: ObjectIdentifier
        var generation: UInt64
        var columns: Int
        var runs: [Range<Int>]
    }

    private var cachedRows: [CachedRow?] = []

    /// Rows rescanned by the last call to `mask`, for tests and diagnostics.
    public private(set) var lastRescannedRowCount = 0

    public init() {}

    /// The mask for what `terminal` shows right now.
    ///
    /// - Parameters:
    ///   - terminal: The terminal whose visible rows are scanned.
    ///   - cellWidth: Width of one cell, in canvas points.
    ///   - cellHeight: Height of one cell, in canvas points.
    public func mask(for terminal: Terminal, cellWidth: Double, cellHeight: Double) -> VTGOcclusionMask {
        let rows = terminal.rows
        let columns = terminal.cols
        if cachedRows.count != rows {
            cachedRows = Array(repeating: nil, count: rows)
        }
        lastRescannedRowCount = 0
        var rects: [VTGLayerClip] = []
        for row in 0..<rows {
            guard let line = terminal.getLine(row: row) else {
                continue
            }
            let runs = inkRuns(row: row, line: line, columns: columns)
            // A double-width line draws each column two cells wide.
            let scale = line.renderMode == .single ? 1.0 : 2.0
            for run in runs {
                rects.append(VTGLayerClip(
                    x: Double(run.lowerBound) * cellWidth * scale,
                    y: Double(row) * cellHeight,
                    width: Double(run.count) * cellWidth * scale,
                    height: cellHeight
                ))
            }
        }
        return VTGOcclusionMask(rects: rects)
    }

    private func inkRuns(row: Int, line: BufferLine, columns: Int) -> [Range<Int>] {
        let lineID = ObjectIdentifier(line)
        if let cached = cachedRows[row],
           cached.lineID == lineID, cached.generation == line.generation, cached.columns == columns {
            return cached.runs
        }
        lastRescannedRowCount += 1
        let runs = Self.inkRuns(in: line, columns: columns)
        cachedRows[row] = CachedRow(lineID: lineID, generation: line.generation, columns: columns, runs: runs)
        return runs
    }

    /// The runs of inked columns in one line. A wide character's ink covers
    /// every column it occupies.
    static func inkRuns(in line: BufferLine, columns: Int) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var runStart: Int?
        var runEnd = 0
        let limit = min(columns, line.count)
        var column = 0
        while column < limit {
            let cell = line[column]
            let width = max(1, Int(cell.width))
            if cell.width != 0, VTGCellInkRule.hasInk(cell) {
                if runStart == nil {
                    runStart = column
                }
                runEnd = min(limit, column + width)
            } else if cell.width != 0, let start = runStart, column >= runEnd {
                runs.append(start..<runEnd)
                runStart = nil
            }
            column += cell.width == 0 ? 1 : width
        }
        if let start = runStart {
            runs.append(start..<runEnd)
        }
        return runs
    }
}
