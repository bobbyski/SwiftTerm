#if os(macOS)
import AppKit

public extension TerminalView {
    /// Captures retained text using the same color/font mapping as the terminal.
    /// The bookmark excludes earlier echo. Screen changes and eviction throw.
    /// Wide characters are emitted once; soft wraps do not add hard newlines.
    /// Document foreground changes default ink while preserving ANSI colors.
    func attributedText(since bookmark: TerminalTextBookmark, documentStyle: Bool = false, documentForeground: NSColor? = nil, documentBackground: NSColor? = nil) throws -> NSAttributedString {
        let terminal = getTerminal()
        let (start, end) = try terminal.rangeForTextCapture(since: bookmark)
        let result = NSMutableAttributedString(string: "")
        for row in start.row...end.row {
            let line = terminal.buffer.lines[row]
            var column = row == start.row ? start.col : 0
            let limit = min(row == end.row ? end.col : terminal.cols, line.getTrimmedLength())
            while column < limit {
                let cell = line[column]
                let width = max(1, Int(cell.width))
                let text: String
                if cell.attribute.style.contains(.invisible) { text = String(repeating: " ", count: width) }
                else { text = cell.code == 0 ? " " : String(terminal.getCharacter(for: cell)) }
                result.append(NSAttributedString(string: text,
                    attributes: transcriptAttributes(cell.attribute, documentStyle: documentStyle, documentForeground: documentForeground, documentBackground: documentBackground)))
                column += width
            }
            if row < end.row, !terminal.buffer.lines[row + 1].isWrapped {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }
    /// Styles persisted rows with the terminal's font mapping. In document mode,
    /// documentForeground replaces only normal default ink, retaining ANSI colors.
    func attributedText(lines: [TerminalTranscriptLine], documentStyle: Bool = false, documentForeground: NSColor? = nil, documentBackground: NSColor? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for (index, line) in lines.enumerated() {
            if index > 0, !line.isWrapped { result.append(NSAttributedString(string: "\n")) }
            for run in line.runs {
                func color(_ value: TerminalTranscriptColor) -> Attribute.Color {
                    switch value {
                    case .defaultColor: return .defaultColor
                    case .defaultInvertedColor: return .defaultInvertedColor
                    case .rgb(let rgb):
                        return .trueColor(red: UInt8((rgb >> 16) & 255), green: UInt8((rgb >> 8) & 255), blue: UInt8(rgb & 255))
                    }
                }
                let attribute = Attribute(fg: color(run.foreground), bg: color(run.background),
                    style: CharacterStyle(rawValue: run.style),
                    underlineStyle: UnderlineStyle(rawValue: run.underline) ?? .none,
                    underlineColor: run.underlineColor.map(color))
                result.append(NSAttributedString(string: run.text, attributes: transcriptAttributes(attribute, documentStyle: documentStyle, documentForeground: documentForeground, documentBackground: documentBackground)))
            }
        }
        return result
    }

    /// Document presentation inherits its surface while retaining explicit ANSI backgrounds.
    private func transcriptAttributes(_ attribute: Attribute, documentStyle: Bool, documentForeground: NSColor? = nil, documentBackground: NSColor? = nil) -> [NSAttributedString.Key: Any] {
        // Resolve dimming after choosing the document surface, not against the
        // terminal's unrelated canvas. Explicit ANSI backgrounds remain authoritative.
        let resolved = Attribute(fg: attribute.fg, bg: attribute.bg,
            style: documentStyle ? attribute.style.subtracting(.dim) : attribute.style,
            underlineStyle: attribute.underlineStyle, underlineColor: attribute.underlineColor)
        var attributes = getAttributes(resolved, withUrl: false) ?? [:]
        if documentStyle, !attribute.style.contains(.inverse) {
            var ink = attributes[.foregroundColor] as? NSColor
            if attribute.fg == .defaultColor, let documentForeground { ink = documentForeground }
            if attribute.style.contains(.dim), let currentInk = ink {
                let surface = attribute.bg == .defaultColor
                    ? (documentBackground ?? nativeBackgroundColor)
                    : ((attributes[.backgroundColor] as? NSColor) ?? nativeBackgroundColor)
                ink = currentInk.dimmedColor(towards: surface)
            }
            if let ink {
                attributes[.foregroundColor] = ink
                if attribute.style.contains(.underline), attribute.underlineColor == nil {
                    attributes[.underlineColor] = ink
                }
                if attribute.style.contains(.crossedOut) { attributes[.strikethroughColor] = ink }
            }
        } else if documentStyle, attribute.style.contains(.dim) {
            // Inverse presentation keeps the terminal's channel mapping.
            attributes = getAttributes(attribute, withUrl: false) ?? [:]
        }
        if documentStyle, attribute.bg == .defaultColor, !attribute.style.contains(.inverse) {
            attributes.removeValue(forKey: .backgroundColor)
        }
        return attributes
    }

}
#endif
