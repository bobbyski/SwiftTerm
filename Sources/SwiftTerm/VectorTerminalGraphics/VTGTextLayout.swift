import Foundation
#if canImport(CoreText)
import CoreText
import CoreGraphics
#endif

/// Measured geometry of a laid-out rich text object, in scene coordinates.
public struct VTGTextMetrics: Equatable {
    /// Unrotated frame the text occupies. For a `textBox` this is the box.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var lineCount: Int
    /// Baselines measured from the top of the frame.
    public var firstBaseline: Double
    public var lastBaseline: Double
    /// Whether lines were dropped or shortened to fit the box.
    public var truncated: Bool
    /// Font families actually used, in first-use order.
    public var resolvedFonts: [String]

    /// Axis-aligned bounds including rotation, for growth and hit testing.
    public var rotatedBounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        (x, y, x + width, y + height)
    }
}

/// Lays out ``VTGRichText``.
///
/// Rendering, `textMeasure?`, and page growth all call this, so what a program
/// measures is exactly what it gets drawn. On platforms without Core Text the
/// metrics are an estimate from the font size; nothing is drawn there by this
/// type.
public enum VTGTextLayout {
    /// Measure a rich text object.
    public static func metrics(for text: VTGRichText) -> VTGTextMetrics {
        #if canImport(CoreText)
        return layout(text).metrics
        #else
        return estimatedMetrics(for: text)
        #endif
    }

    /// Axis-aligned scene bounds, including rotation about (`x`, `y`).
    static func bounds(for text: VTGRichText) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let m = metrics(for: text)
        guard text.angle != 0 else {
            return m.rotatedBounds
        }
        let radians = text.angle * .pi / 180
        let c = cos(radians), s = sin(radians)
        let corners = [
            (m.x, m.y), (m.x + m.width, m.y),
            (m.x, m.y + m.height), (m.x + m.width, m.y + m.height)
        ].map { point -> (Double, Double) in
            let dx = point.0 - text.x, dy = point.1 - text.y
            return (text.x + dx * c - dy * s, text.y + dx * s + dy * c)
        }
        return (
            corners.map(\.0).min() ?? m.x,
            corners.map(\.1).min() ?? m.y,
            corners.map(\.0).max() ?? m.x,
            corners.map(\.1).max() ?? m.y
        )
    }

    #if !canImport(CoreText)
    private static func estimatedMetrics(for text: VTGRichText) -> VTGTextMetrics {
        var lines: [Double] = [0]
        var lineHeights: [Double] = [0]
        for run in text.runs {
            let size = run.style.resolvedSize
            if run.isLineBreak {
                lines.append(0)
                lineHeights.append(size * 1.2)
                continue
            }
            lines[lines.count - 1] += Double(run.text.count) * size * 0.6
            lineHeights[lineHeights.count - 1] = max(lineHeights[lineHeights.count - 1], size * 1.2)
        }
        let width = text.width ?? (lines.max() ?? 0)
        let height = text.height ?? lineHeights.reduce(0, +)
        return VTGTextMetrics(
            x: text.x, y: text.y, width: width, height: height,
            lineCount: lines.count,
            firstBaseline: (lineHeights.first ?? 0) * 0.8,
            lastBaseline: height - (lineHeights.last ?? 0) * 0.2,
            truncated: false,
            resolvedFonts: []
        )
    }
    #endif
}

#if canImport(CoreText)
/// Attribute keys Core Text does not draw by itself; the renderer paints them.
let vtgBackgroundAttribute = NSAttributedString.Key("VTGRunBackground")
let vtgStrikeAttribute = NSAttributedString.Key("VTGRunStrike")

extension VTGTextLayout {
    /// One positioned line, ready to draw.
    struct Line {
        var line: CTLine
        /// Left end of the baseline, in scene coordinates.
        var origin: CGPoint
        var ascent: CGFloat
        var descent: CGFloat
    }

    struct Result {
        var metrics: VTGTextMetrics
        var lines: [Line]
        /// Clip rectangle for a box; `nil` for unbounded text.
        var clip: CGRect?
        /// The laid-out string and which style covers which range, for
        /// exporters that re-express the layout in another format.
        var string: String = ""
        var styleRanges: [(range: NSRange, style: VTGTextStyle)] = []
    }

    /// Full layout: positioned lines plus metrics.
    static func layout(_ text: VTGRichText) -> Result {
        var fontsUsed: [String] = []
        var styleRanges: [(range: NSRange, style: VTGTextStyle)] = []
        let attributed = attributedString(for: text, fontsUsed: &fontsUsed, styleRanges: &styleRanges)
        let isBox = text.kind == .box
        let insets = isBox ? text.insets : .zero

        // Available width for wrapping. Unwrapped text is measured first so
        // alignment can be applied against the widest line instead of an
        // infinitely wide column.
        let wraps = text.wrap != .none
        var availableWidth: CGFloat
        if isBox, let width = text.width {
            availableWidth = CGFloat(max(1, width - insets.left - insets.right))
        } else if let width = text.width, wraps {
            availableWidth = CGFloat(max(1, width))
        } else {
            availableWidth = .greatestFiniteMagnitude / 4
        }
        let effectiveWidth = (isBox && !wraps) ? CGFloat.greatestFiniteMagnitude / 4 : availableWidth

        var lines = typesetLines(attributed, width: wraps ? effectiveWidth : .greatestFiniteMagnitude / 4, text: text)
        let widest = lines.map { CGFloat(CTLineGetTypographicBounds($0.line, nil, nil, nil)) }.max() ?? 0
        if !isBox && availableWidth > CGFloat.greatestFiniteMagnitude / 8 {
            availableWidth = ceil(widest)
        }
        // Box without wrapping still aligns within the box.
        let alignmentWidth: CGFloat = isBox
            ? CGFloat(max(0, (text.width ?? Double(widest)) - insets.left - insets.right))
            : availableWidth

        // Vertical positions, top-down from 0.
        var cursor: CGFloat = 0
        var positioned: [(Line, CGFloat)] = []
        for (index, var entry) in lines.enumerated() {
            let advanceAbove = entry.ascent
            let lineAdvance = text.lineHeight.map { CGFloat($0) }
            let top = cursor
            let baseline: CGFloat
            if let lineAdvance {
                // Fixed advance: centre the glyph box in the line.
                let slack = lineAdvance - (entry.ascent + entry.descent)
                baseline = top + slack / 2 + entry.ascent
                cursor = top + lineAdvance
            } else {
                baseline = top + advanceAbove
                cursor = baseline + entry.descent + entry.leading
            }
            entry.baselineFromTop = baseline
            lines[index] = entry
            positioned.append((Line(line: entry.line, origin: .zero, ascent: entry.ascent, descent: entry.descent), baseline))
        }
        let contentHeight: CGFloat = lines.last.map { entry in
            text.lineHeight != nil ? cursor : entry.baselineFromTop + entry.descent
        } ?? 0

        // Fit to the box height.
        var truncated = false
        var boxHeight: CGFloat? = nil
        if isBox, let height = text.height, text.overflow != .grow {
            let inner = CGFloat(max(0, height - insets.top - insets.bottom))
            boxHeight = inner
            var fitting = positioned.prefix { $0.1 + $0.0.descent <= inner + 0.5 }
            if fitting.count < positioned.count {
                truncated = true
                if text.overflow == .ellipsis {
                    if fitting.isEmpty, let first = positioned.first {
                        fitting = [first]
                    }
                    if let last = fitting.last, let index = fitting.indices.last {
                        // `fitting` is a prefix, so its indexes are the typeset line indexes.
                        let truncatedLine = ellipsizedLine(
                            from: attributed,
                            lineIndex: index,
                            lines: lines,
                            width: alignmentWidth
                        )
                        var replaced = last
                        replaced.0.line = truncatedLine
                        fitting[index] = replaced
                    }
                }
                positioned = Array(fitting)
            }
        }

        // Frame of the object.
        let frameWidth: Double
        let frameHeight: Double
        if isBox {
            frameWidth = text.width ?? Double(widest) + insets.left + insets.right
            if let boxHeight {
                frameHeight = Double(boxHeight) + insets.top + insets.bottom
            } else {
                frameHeight = Double(contentHeight) + insets.top + insets.bottom
            }
        } else {
            frameWidth = Double(alignmentWidth)
            frameHeight = Double(contentHeight)
        }

        var frameX = text.x
        var frameY = text.y
        if !isBox {
            switch text.alignment {
            case .center: frameX -= frameWidth / 2
            case .right: frameX -= frameWidth
            case .left, .justify: break
            }
            switch text.baseline {
            case .top: break
            case .alphabetic: frameY -= Double(positioned.first?.1 ?? 0)
            case .middle: frameY -= frameHeight / 2
            case .bottom: frameY -= frameHeight
            }
        }

        // Vertical alignment inside a box that is taller than its content.
        var contentOffsetY: CGFloat = 0
        if isBox, let boxHeight {
            let used = positioned.last.map { $0.1 + $0.0.descent } ?? 0
            switch text.verticalAlignment {
            case .top: break
            case .middle: contentOffsetY = max(0, (boxHeight - used) / 2)
            case .bottom: contentOffsetY = max(0, boxHeight - used)
            }
        }

        let originX = CGFloat(frameX + insets.left)
        let originY = CGFloat(frameY + insets.top) + contentOffsetY
        let resultLines = positioned.map { entry -> Line in
            var line = entry.0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line.line, nil, nil, nil))
            let trailing = CGFloat(CTLineGetTrailingWhitespaceWidth(line.line))
            let visibleWidth = lineWidth - trailing
            var dx: CGFloat = 0
            switch text.alignment {
            case .center: dx = (alignmentWidth - visibleWidth) / 2
            case .right: dx = alignmentWidth - visibleWidth
            case .left: dx = 0
            case .justify:
                // Every line but the last is stretched to the full width.
                dx = 0
                if entry.0.line !== positioned.last?.0.line, visibleWidth > 0,
                   let justified = CTLineCreateJustifiedLine(line.line, 1, Double(alignmentWidth)) {
                    line.line = justified
                }
            }
            line.origin = CGPoint(x: originX + max(0, dx), y: originY + entry.1)
            return line
        }

        let metrics = VTGTextMetrics(
            x: frameX,
            y: frameY,
            width: frameWidth,
            height: frameHeight,
            lineCount: resultLines.count,
            firstBaseline: Double(positioned.first?.1 ?? 0) + insets.top + Double(contentOffsetY),
            lastBaseline: Double(positioned.last?.1 ?? 0) + insets.top + Double(contentOffsetY),
            truncated: truncated,
            resolvedFonts: fontsUsed
        )
        let clip: CGRect? = (isBox && text.height != nil && text.overflow != .grow)
            ? CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
            : nil
        return Result(metrics: metrics, lines: resultLines, clip: clip, string: attributed.string, styleRanges: styleRanges)
    }

    private struct TypesetLine {
        var line: CTLine
        var range: CFRange
        var ascent: CGFloat
        var descent: CGFloat
        var leading: CGFloat
        var baselineFromTop: CGFloat = 0
    }

    private static func typesetLines(_ attributed: NSAttributedString, width: CGFloat, text: VTGRichText) -> [TypesetLine] {
        let length = attributed.length
        guard length > 0 else {
            return []
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var lines: [TypesetLine] = []
        var start = 0
        let wrapsByChar = text.wrap == .char
        while start < length {
            var count = wrapsByChar
                ? CTTypesetterSuggestClusterBreak(typesetter, start, Double(width))
                : CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            if count <= 0 {
                count = 1
            }
            // A hard break ends the line but is not drawn.
            let range = CFRange(location: start, length: count)
            var lineRange = range
            let substring = (attributed.string as NSString).substring(with: NSRange(location: start, length: count))
            if substring.hasSuffix("\n") {
                lineRange.length -= 1
            }
            let line = CTTypesetterCreateLine(typesetter, lineRange)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            if lineRange.length == 0 {
                // An empty line still takes the height of its break's font.
                let font = attributed.attribute(
                    NSAttributedString.Key(kCTFontAttributeName as String),
                    at: min(start, length - 1),
                    effectiveRange: nil
                )
                if let font {
                    let ctFont = font as! CTFont
                    ascent = CTFontGetAscent(ctFont)
                    descent = CTFontGetDescent(ctFont)
                    leading = CTFontGetLeading(ctFont)
                }
            }
            lines.append(TypesetLine(line: line, range: lineRange, ascent: ascent, descent: descent, leading: leading))
            start += count
        }
        return lines
    }

    private static func ellipsizedLine(
        from attributed: NSAttributedString,
        lineIndex: Int,
        lines: [TypesetLine],
        width: CGFloat
    ) -> CTLine {
        let line = lines[lineIndex]
        let rest = NSRange(location: line.range.location, length: attributed.length - line.range.location)
        let tail = NSMutableAttributedString(attributedString: attributed.attributedSubstring(from: rest))
        tail.mutableString.replaceOccurrences(of: "\n", with: " ", options: [], range: NSRange(location: 0, length: tail.length))
        let full = CTLineCreateWithAttributedString(tail)
        let attributes = tail.length > 0 ? tail.attributes(at: 0, effectiveRange: nil) : [:]
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: attributes))
        return CTLineCreateTruncatedLine(full, Double(max(1, width)), .end, token) ?? full
    }

    private static func attributedString(
        for text: VTGRichText,
        fontsUsed: inout [String],
        styleRanges: inout [(range: NSRange, style: VTGTextStyle)]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in text.runs {
            let style = run.style
            let font = VTGFontResolver.font(for: style)
            let family = CTFontCopyFamilyName(font) as String
            if !fontsUsed.contains(family) {
                fontsUsed.append(family)
            }
            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.resolvedColor.textCGColor
            ]
            if let tracking = style.tracking, tracking != 0 {
                attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = tracking
            }
            if let underline = style.underline, underline != .none {
                attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = underlineValue(underline)
                if let color = style.underlineColor {
                    attributes[NSAttributedString.Key(kCTUnderlineColorAttributeName as String)] = color.textCGColor
                }
            }
            if let background = style.background, background.alpha > 0 {
                attributes[vtgBackgroundAttribute] = background.textCGColor
            }
            if style.strike == true {
                attributes[vtgStrikeAttribute] = style.resolvedColor.textCGColor
            }
            if let lineHeight = style.lineHeight, lineHeight > 0 {
                var value = CGFloat(lineHeight)
                let settings = [
                    CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: &value),
                    CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: &value)
                ]
                attributes[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] = CTParagraphStyleCreate(settings, settings.count)
            }
            let piece = NSAttributedString(string: run.isLineBreak ? "\n" : run.text, attributes: attributes)
            styleRanges.append((NSRange(location: result.length, length: piece.length), style))
            result.append(piece)
        }
        return result
    }

    private static func underlineValue(_ underline: VTGTextUnderline) -> Int32 {
        switch underline {
        case .none:
            return Int32(CTUnderlineStyle().rawValue)
        case .single, .curly:
            return Int32(CTUnderlineStyle.single.rawValue)
        case .double:
            return Int32(CTUnderlineStyle.double.rawValue)
        case .dotted:
            return Int32(CTUnderlineStyle.single.rawValue | CTUnderlineStyleModifiers.patternDot.rawValue)
        case .dashed:
            return Int32(CTUnderlineStyle.single.rawValue | CTUnderlineStyleModifiers.patternDash.rawValue)
        }
    }

    /// SVG for a rich text object: one `<text>` per laid-out line, one
    /// `<tspan>` per styled run, positioned from the same layout the renderer
    /// draws.
    static func svgFragment(for text: VTGRichText) -> String {
        let result = layout(text)
        let string = result.string as NSString
        var fragments: [String] = []
        for line in result.lines {
            let lineRange = CTLineGetStringRange(line.line)
            var spans: [String] = []
            for entry in result.styleRanges {
                let overlap = NSIntersectionRange(entry.range, NSRange(location: lineRange.location, length: lineRange.length))
                guard overlap.length > 0 else { continue }
                let piece = string.substring(with: overlap).replacingOccurrences(of: "\n", with: "")
                guard !piece.isEmpty else { continue }
                let offset = CTLineGetOffsetForStringIndex(line.line, overlap.location, nil)
                let style = entry.style
                let color = style.resolvedColor
                var attributes = "x=\"\(svgTextNumber(Double(line.origin.x + offset)))\""
                attributes += " font-family=\"\(svgTextEscape(svgFamily(style.font)))\""
                attributes += " font-size=\"\(svgTextNumber(style.resolvedSize))\""
                if style.resolvedWeight != 400 { attributes += " font-weight=\"\(style.resolvedWeight)\"" }
                if style.italic == true { attributes += " font-style=\"italic\"" }
                attributes += " fill=\"\(svgTextColor(color))\""
                if color.alpha < 1 { attributes += " fill-opacity=\"\(svgTextNumber(color.alpha))\"" }
                var decorations: [String] = []
                if let underline = style.underline, underline != .none { decorations.append("underline") }
                if style.strike == true { decorations.append("line-through") }
                if !decorations.isEmpty { attributes += " text-decoration=\"\(decorations.joined(separator: " "))\"" }
                spans.append("<tspan \(attributes)>\(svgTextEscape(piece))</tspan>")
            }
            guard !spans.isEmpty else { continue }
            fragments.append("<text y=\"\(svgTextNumber(Double(line.origin.y)))\" xml:space=\"preserve\">\(spans.joined())</text>")
        }
        var body = fragments.joined()
        if text.angle != 0 {
            body = "<g transform=\"rotate(\(svgTextNumber(text.angle)) \(svgTextNumber(text.x)) \(svgTextNumber(text.y)))\">\(body)</g>"
        }
        return "<g data-vtg-text=\"\(text.kind.rawValue)\" id=\"\(svgTextEscape(text.id))\">\(body)</g>"
    }

    private static func svgFamily(_ family: String?) -> String {
        switch (family ?? "sans").lowercased() {
        case "sans", "system": return "system-ui, sans-serif"
        case "serif": return "serif"
        case "mono", "terminal", "monospace": return "ui-monospace, monospace"
        default: return family ?? "sans-serif"
        }
    }

    private static func svgTextNumber(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(rounded)
    }

    private static func svgTextColor(_ color: VTGColor) -> String {
        func channel(_ value: Double) -> String {
            String(format: "%02x", Int((min(1, max(0, value)) * 255).rounded()))
        }
        return "#\(channel(color.red))\(channel(color.green))\(channel(color.blue))"
    }

    private static func svgTextEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Draw a rich text object into a top-left-origin (flipped) context.
    static func draw(_ text: VTGRichText, in context: CGContext) {
        let result = layout(text)
        context.saveGState()
        if text.angle != 0 {
            context.translateBy(x: CGFloat(text.x), y: CGFloat(text.y))
            context.rotate(by: CGFloat(text.angle * .pi / 180))
            context.translateBy(x: CGFloat(-text.x), y: CGFloat(-text.y))
        }
        if let clip = result.clip {
            context.clip(to: clip)
        }
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for line in result.lines {
            drawDecorations(of: line, in: context, strikes: false)
            context.textPosition = line.origin
            CTLineDraw(line.line, context)
            drawDecorations(of: line, in: context, strikes: true)
        }
        context.restoreGState()
    }

    /// Paint run backgrounds (before the glyphs) or strike-throughs (after).
    private static func drawDecorations(of line: Line, in context: CGContext, strikes: Bool) {
        let runs = CTLineGetGlyphRuns(line.line) as! [CTRun]
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let key = strikes ? vtgStrikeAttribute : vtgBackgroundAttribute
            guard let value = attributes[key] else {
                continue
            }
            let color = value as! CGColor
            let range = CTRunGetStringRange(run)
            let startX = CTLineGetOffsetForStringIndex(line.line, range.location, nil)
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil))
            context.saveGState()
            if strikes {
                let font = attributes[kCTFontAttributeName as String].map { $0 as! CTFont }
                let xHeight = font.map { CTFontGetXHeight($0) } ?? ascent * 0.5
                let thickness = max(1, (font.map { CTFontGetUnderlineThickness($0) } ?? 1))
                context.setFillColor(color)
                context.fill(CGRect(
                    x: line.origin.x + startX,
                    y: line.origin.y - xHeight / 2 - thickness / 2,
                    width: width,
                    height: thickness
                ))
            } else {
                context.setFillColor(color)
                context.fill(CGRect(
                    x: line.origin.x + startX,
                    y: line.origin.y - line.ascent,
                    width: width,
                    height: line.ascent + line.descent
                ))
            }
            context.restoreGState()
        }
    }
}

/// The families this host can draw with, for `fonts?`.
enum VTGFontCatalog {
    static var availableFamilies: [String] { VTGFontResolver.availableFamilies() }
    static var defaultFamily: String { VTGFontResolver.defaultFamily }
}

/// Resolves a style's family, weight, and slant to a Core Text font.
enum VTGFontResolver {
    private static let lock = NSLock()
    private static var cache: [String: CTFont] = [:]

    /// Generic family names every host understands.
    static let genericFamilies = ["sans", "serif", "mono", "terminal"]

    static func font(for style: VTGTextStyle) -> CTFont {
        let size = CGFloat(style.resolvedSize)
        let weight = style.resolvedWeight
        let italic = style.italic ?? false
        let family = style.font ?? "sans"
        let key = "\(family)|\(size)|\(weight)|\(italic)"
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let font = makeFont(family: family, size: size, weight: weight, italic: italic)
        lock.lock()
        if cache.count > 512 {
            cache.removeAll()
        }
        cache[key] = font
        lock.unlock()
        return font
    }

    private static func makeFont(family: String, size: CGFloat, weight: Int, italic: Bool) -> CTFont {
        let base: CTFont
        switch family.lowercased() {
        case "sans", "system", "":
            base = CTFontCreateUIFontForLanguage(.system, size, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        case "mono", "terminal", "monospace":
            base = CTFontCreateUIFontForLanguage(.userFixedPitch, size, nil)
                ?? CTFontCreateWithName("Menlo" as CFString, size, nil)
        case "serif":
            base = CTFontCreateWithName("Times New Roman" as CFString, size, nil)
        default:
            let candidate = CTFontCreateWithName(family as CFString, size, nil)
            let resolved = CTFontCopyFamilyName(candidate) as String
            let postScript = CTFontCopyPostScriptName(candidate) as String
            if resolved.caseInsensitiveCompare(family) == .orderedSame
                || postScript.caseInsensitiveCompare(family) == .orderedSame {
                base = candidate
            } else {
                // Unknown family: fall back to the system face rather than
                // whatever Core Text substituted.
                base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? candidate
            }
        }
        return applying(weight: weight, italic: italic, to: base, size: size)
    }

    private static func applying(weight: Int, italic: Bool, to base: CTFont, size: CGFloat) -> CTFont {
        let familyName = CTFontCopyFamilyName(base)
        var traits: [CFString: Any] = [kCTFontWeightTrait: weightTrait(weight)]
        if italic {
            traits[kCTFontSymbolicTrait] = CTFontSymbolicTraits.traitItalic.rawValue
        }
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: familyName,
            kCTFontTraitsAttribute: traits
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let candidate = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        if (CTFontCopyFamilyName(candidate) as String) == (familyName as String) {
            return candidate
        }
        // Symbolic traits as a last resort.
        var symbolic = CTFontSymbolicTraits()
        if weight >= 600 { symbolic.insert(.traitBold) }
        if italic { symbolic.insert(.traitItalic) }
        guard !symbolic.isEmpty else {
            return base
        }
        return CTFontCreateCopyWithSymbolicTraits(base, size, nil, symbolic, symbolic) ?? base
    }

    private static func weightTrait(_ weight: Int) -> CGFloat {
        switch min(900, max(100, weight)) {
        case ..<150: return -0.8
        case ..<250: return -0.6
        case ..<350: return -0.4
        case ..<450: return 0
        case ..<550: return 0.23
        case ..<650: return 0.3
        case ..<750: return 0.4
        case ..<850: return 0.56
        default: return 0.62
        }
    }

    /// Installed font family names.
    static func availableFamilies() -> [String] {
        (CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    /// The family `sans` resolves to on this host.
    static var defaultFamily: String {
        CTFontCopyFamilyName(font(for: VTGTextStyle())) as String
    }
}

extension VTGColor {
    /// Core Graphics color for text attributes. Named apart from the AppKit
    /// overlay's `cgColor` because this one is available wherever Core Text is.
    var textCGColor: CGColor {
        CGColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}
#endif
