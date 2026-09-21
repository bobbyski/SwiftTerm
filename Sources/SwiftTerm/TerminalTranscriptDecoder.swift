import Foundation

/// Projects a recording into immutable rows using the normal terminal parser.
/// Rows leaving the viewport can no longer be edited by ordinary cursor motion,
/// so they are emitted immediately. Memory stays bounded by terminal scrollback.
/// Screen resets that invalidate this projection report an error; raw recordings
/// remain the authoritative source for full interactive replay.
public final class TerminalTranscriptDecoder: TerminalDelegate {
    private let options: TerminalOptions
    private lazy var terminal = Terminal(delegate: self, options: options)
    private let onLine: (TerminalTranscriptLine) throws -> Void
    private var bufferIdentity: ObjectIdentifier?
    private var nextRow = 0
    private var failure: Error?
    private var finished = false
    /// Whether the final cursor follows a completed line, without an extra blank page.
    public private(set) var endsWithNewline = false

    /// Creates a decoder at the command's recorded dimensions.
    public init(columns: Int, rows: Int, onLine: @escaping (TerminalTranscriptLine) throws -> Void) {
        options = TerminalOptions(cols: max(2, min(1000, columns)), rows: max(2, min(200, rows)), scrollback: 256)
        self.onLine = onLine
        bufferIdentity = ObjectIdentifier(terminal.buffer)
    }

    /// Parses an owned chunk; UTF-8 and escape sequences may cross chunks.
    public func feed(_ data: Data) throws {
        guard !finished else { throw ProjectionError.alreadyFinished }
        if let failure { throw failure }
        terminal.feed(byteArray: Array(data))
        try validateBuffer()
        if let failure { throw failure }
    }

    /// Emits remaining visible rows through the final cursor row, exactly once.
    public func finish() throws {
        guard !finished else { throw ProjectionError.alreadyFinished }
        try validateBuffer()
        if let failure { throw failure }
        let end = terminal.buffer.linesTop + terminal.buffer.yBase + terminal.buffer.y
        let last = terminal.getScrollInvariantLine(row: end)
        endsWithNewline = end > 0 && terminal.buffer.x == 0 && last?.getTrimmedLength() == 0
        try emit(until: endsWithNewline ? end : end + 1)
        finished = true
    }

    /// Replay never sends terminal responses to a process or executes commands.
    public func send(source: Terminal, data: ArraySlice<UInt8>) {}

    /// Called by the existing parser after each scroll, before history eviction.
    public func scrolled(source: Terminal, yDisp: Int) {
        guard failure == nil else { return }
        do {
            try validateBuffer()
            try emit(until: terminal.buffer.linesTop + terminal.buffer.yBase)
        } catch { failure = error }
    }

    /// Latches transient alternate-screen use even when normal mode returns in one chunk.
    public func bufferActivated(source: Terminal) {
        if source.isCurrentBufferAlternate, failure == nil {
            failure = ProjectionError.screenChanged
        }
    }

    private func validateBuffer() throws {
        guard ObjectIdentifier(terminal.buffer) == bufferIdentity,
              !terminal.isCurrentBufferAlternate,
              terminal.buffer.linesTop + terminal.buffer.yBase >= nextRow else {
            throw ProjectionError.screenChanged
        }
    }

    private func emit(until end: Int) throws {
        while nextRow < end {
            guard let line = terminal.getScrollInvariantLine(row: nextRow) else {
                throw ProjectionError.historyLost
            }
            try onLine(snapshot(line))
            nextRow += 1
        }
    }

    private func snapshot(_ line: BufferLine) -> TerminalTranscriptLine {
        var runs: [TerminalTranscriptRun] = []
        var column = 0
        while column < line.getTrimmedLength() {
            let cell = line[column]
            let width = max(1, Int(cell.width))
            let attribute = cell.attribute
            let text = attribute.style.contains(.invisible) ? String(repeating: " ", count: width)
                : (cell.code == 0 ? " " : String(terminal.getCharacter(for: cell)))
            let run = TerminalTranscriptRun(text: text, foreground: resolve(attribute.fg),
                background: resolve(attribute.bg), style: attribute.style.rawValue,
                underline: attribute.underlineStyle.rawValue)
            if let last = runs.last, last.foreground == run.foreground, last.background == run.background,
               last.style == run.style, last.underline == run.underline {
                runs[runs.count - 1].text += text
            } else { runs.append(run) }
            column += width
        }
        return TerminalTranscriptLine(isWrapped: line.isWrapped, runs: runs)
    }

    private func resolve(_ color: Attribute.Color) -> TerminalTranscriptColor {
        let resolved: Color
        switch color {
        case .ansi256(let code): resolved = terminal.ansiColors[Int(code)]
        case .defaultColor: return .defaultColor
        case .defaultInvertedColor: return .defaultInvertedColor
        case .trueColor(let red, let green, let blue):
            return .rgb(UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue))
        }
        return .rgb(UInt32(resolved.red >> 8) << 16 | UInt32(resolved.green >> 8) << 8 | UInt32(resolved.blue >> 8))
    }

    /// A recording cannot be presented as complete static text in these cases.
    public enum ProjectionError: Error {
        case screenChanged
        case historyLost
        case alreadyFinished
    }
}
