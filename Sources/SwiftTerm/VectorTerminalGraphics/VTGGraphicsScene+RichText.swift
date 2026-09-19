import Foundation

/// `textStyle`, `styledText`, `attrText`, and `textBox` for the retained scene.
extension VTGGraphicsScene {
    /// Define or replace a named style in the session registry.
    func defineTextStyle(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"], Self.isValidTextIdentifier(id) else {
            return
        }
        var style = VTGTextStyle()
        if let parent = command.parameters["inherit"].flatMap(textStyles.style(named:)) {
            style = parent
        }
        textStyles.define(id, style: style.overlaid(with: command.textStyleAttributes()))
    }

    func upsertRichText(_ command: VectorTerminalGraphicsCommand) {
        guard let text = parseRichText(command) else {
            return
        }
        upsert(.richText(text), command: command)
    }

    /// Build a rich text object from a command, resolving every style now so
    /// the retained object is self-contained: redefining a style later does
    /// not repaint text already drawn with it.
    func parseRichText(_ command: VectorTerminalGraphicsCommand) -> VTGRichText? {
        let kind: VTGRichText.Kind
        if command.name == "textMeasure?" {
            kind = inferredMeasureKind(command)
        } else if let named = VTGRichText.Kind(rawValue: command.name) {
            kind = named
        } else {
            return nil
        }
        let id = command.parameters["id"] ?? ""
        guard command.name == "textMeasure?" || Self.isValidTextIdentifier(id) else {
            return nil
        }
        let base = baseTextStyle(for: command)
        let runs: [VTGTextRun]
        switch kind {
        case .styled:
            runs = Self.runs(fromPlainText: command.payload ?? "", style: base)
        case .attributed, .box:
            guard let rawRuns = VTGTextRunParser.parse(command.payload ?? "") else {
                return nil
            }
            runs = rawRuns.map { raw in
                if raw.isLineBreak {
                    return .lineBreak(style: base)
                }
                let style = raw.usesBaseStyle
                    ? base
                    : base.overlaid(with: textStyles.style(named: raw.styleRef) ?? VTGTextStyle())
                return VTGTextRun(text: raw.text, style: style)
            }
        }

        var width: Double? = nil
        var height: Double? = nil
        var overflow = command.parameters["overflow"].flatMap(VTGTextOverflow.init(rawValue:)) ?? .clip
        if kind == .box {
            width = command.optionalDouble("w") ?? command.optionalDouble("width")
            let rawHeight = command.optionalDouble("h") ?? command.optionalDouble("height")
            if let rawHeight, rawHeight >= 0 {
                height = rawHeight
            } else {
                // `h=-1`, or no height at all, means the box grows to fit.
                overflow = .grow
            }
        } else {
            width = command.optionalDouble("maxWidth").flatMap { $0 > 0 ? $0 : nil }
        }

        return VTGRichText(
            id: id,
            kind: kind,
            x: command.double("x"),
            y: command.double("y"),
            width: width,
            height: height,
            runs: runs,
            alignment: command.parameters["align"].flatMap(VTGTextAlignment.init(rawValue:)) ?? .left,
            verticalAlignment: command.parameters["valign"].flatMap(VTGTextVerticalAlignment.init(rawValue:)) ?? .top,
            baseline: command.parameters["baseline"].flatMap(VTGTextBaseline.init(rawValue:)) ?? .top,
            wrap: command.parameters["wrap"].flatMap(VTGTextWrap.init(rawValue:)) ?? (kind == .box ? .word : (width == nil ? .none : .word)),
            overflow: overflow,
            insets: command.textInsets(),
            angle: command.double("angle"),
            lineHeight: command.optionalDouble("lineHeight").flatMap { $0 > 0 ? $0 : nil }
        )
    }

    /// `textMeasure?` measures box layout when given a width and height,
    /// attributed layout otherwise.
    private func inferredMeasureKind(_ command: VectorTerminalGraphicsCommand) -> VTGRichText.Kind {
        if let raw = command.parameters["kind"], let kind = VTGRichText.Kind(rawValue: raw) {
            return kind
        }
        return command.parameters["w"] != nil || command.parameters["width"] != nil ? .box : .attributed
    }

    /// The command's named `style`, with any inline attributes laid over it.
    private func baseTextStyle(for command: VectorTerminalGraphicsCommand) -> VTGTextStyle {
        let named = command.parameters["style"].flatMap(textStyles.style(named:)) ?? VTGTextStyle()
        return named.overlaid(with: command.textStyleAttributes())
    }

    /// Plain payload text for `styledText`. A raw newline, if a transport
    /// passes one through, becomes a line break rather than a glyph.
    static func runs(fromPlainText text: String, style: VTGTextStyle) -> [VTGTextRun] {
        var runs: [VTGTextRun] = []
        let pieces = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, piece) in pieces.enumerated() {
            if index > 0 {
                runs.append(.lineBreak(style: style))
            }
            if !piece.isEmpty {
                runs.append(VTGTextRun(text: String(piece), style: style))
            }
        }
        return runs
    }

    static func isValidTextIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else {
            return false
        }
        return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}

extension VectorTerminalGraphicsCommand {
    /// Read a numeric parameter only when present and well formed.
    func optionalDouble(_ key: String) -> Double? {
        parameters[key].flatMap(Double.init)
    }

    /// The text attributes a command sets inline. Absent keys stay `nil` so
    /// they cascade from the named style.
    func textStyleAttributes() -> VTGTextStyle {
        var style = VTGTextStyle()
        if let font = parameters["font"], !font.isEmpty {
            style.font = font
        }
        if let size = optionalDouble("size"), size > 0 {
            style.size = min(size, 2_048)
        }
        if let raw = parameters["weight"] {
            switch raw.lowercased() {
            case "normal", "regular": style.weight = 400
            case "bold": style.weight = 700
            case "light": style.weight = 300
            default:
                if let value = Int(raw) {
                    style.weight = min(900, max(100, value))
                }
            }
        }
        if let slant = parameters["slant"] {
            style.italic = slant == "italic" || slant == "oblique"
        } else if let italic = parameters["italic"] {
            style.italic = italic == "1" || italic == "true"
        }
        if let raw = parameters["color"], let color = VTGColor(hex: raw) {
            style.color = color
        }
        if let raw = parameters["bg"] {
            style.background = raw == "none"
                ? VTGColor(red: 0, green: 0, blue: 0, alpha: 0)
                : VTGColor(hex: raw)
        }
        if let tracking = optionalDouble("tracking") {
            style.tracking = tracking
        }
        if let raw = parameters["underline"] {
            switch raw {
            case "0", "false": style.underline = VTGTextUnderline.none
            case "1", "true": style.underline = .single
            default: style.underline = VTGTextUnderline(rawValue: raw)
            }
        }
        if let raw = parameters["underlineColor"], let color = VTGColor(hex: raw) {
            style.underlineColor = color
        }
        if let raw = parameters["strike"] {
            style.strike = raw == "1" || raw == "true"
        }
        if name == "textStyle", let lineHeight = optionalDouble("lineHeight"), lineHeight > 0 {
            // On a style, line height is a per-run attribute. On a text
            // command it is the object's fixed line advance instead.
            style.lineHeight = lineHeight
        }
        return style
    }

    /// `inset=<px>` or `inset=<top>|<right>|<bottom>|<left>`. The separator is
    /// `|` because a comma would end the header field.
    func textInsets() -> VTGTextInsets {
        guard let raw = parameters["inset"] else {
            return .zero
        }
        let values = raw.split(separator: "|").compactMap { Double($0) }.map { max(0, $0) }
        switch values.count {
        case 1:
            return VTGTextInsets(top: values[0], right: values[0], bottom: values[0], left: values[0])
        case 2:
            return VTGTextInsets(top: values[0], right: values[1], bottom: values[0], left: values[1])
        case 4:
            return VTGTextInsets(top: values[0], right: values[1], bottom: values[2], left: values[3])
        default:
            return .zero
        }
    }
}
