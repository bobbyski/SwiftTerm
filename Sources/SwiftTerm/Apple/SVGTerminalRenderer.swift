//
//  SVGTerminalRenderer.swift
//
//  Experimental SVG export path for TerminalView.
//
//  This is intentionally additive. It snapshots the visible terminal buffer
//  without replacing the existing CoreGraphics or Metal renderers.
//
#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import CoreGraphics

/// Receives the SVG body while SwiftTerm is exporting a terminal snapshot.
///
/// Embedders can use this context to add their own vector layer after the
/// terminal cells have been emitted. The API is deliberately small for the
/// first fork pass so it can evolve without disturbing existing renderers.
public final class SVGRenderContext {
    public let width: CGFloat
    public let height: CGFloat
    public let columns: Int
    public let rows: Int
    public let cellSize: CGSize

    private var fragments: [String] = []

    init(width: CGFloat, height: CGFloat, columns: Int, rows: Int, cellSize: CGSize) {
        self.width = width
        self.height = height
        self.columns = columns
        self.rows = rows
        self.cellSize = cellSize
    }

    /// Appends trusted SVG markup to the exported document body.
    ///
    /// This method intentionally does not escape the supplied string. Use it
    /// for generated SVG fragments, not user-entered text.
    public func appendRawSVG(_ svg: String) {
        fragments.append(svg)
    }

    var body: String {
        fragments.joined(separator: "\n")
    }
}

public extension TerminalView {
    /// Exports the visible terminal contents as an SVG document.
    ///
    /// The SVG exporter is the first concrete SVG surface in the fork. It is
    /// useful for tests, diagnostics, and embedders that want an inspectable
    /// vector representation while the live view continues to use the existing
    /// CoreGraphics or Metal drawing paths.
    ///
    /// - Parameter additionalContent: Optional hook for appending extra SVG
    ///   content, such as host-owned vector overlays.
    /// - Returns: A complete SVG document string.
    func makeSVGSnapshot(additionalContent: ((SVGRenderContext) -> Void)? = nil) -> String {
        let cols = max(terminal.cols, 0)
        let rows = max(terminal.rows, 0)
        let cellWidth = max(cellDimension.width, 1)
        let cellHeight = max(cellDimension.height, 1)
        let width = CGFloat(cols) * cellWidth
        let height = CGFloat(rows) * cellHeight
        let fontName = fontSet.normal.fontName
        let fontSize = max(fontSet.normal.pointSize, 1)
        let baseline = max(fontSize, cellHeight * 0.78)
        let context = SVGRenderContext(width: width,
                                       height: height,
                                       columns: cols,
                                       rows: rows,
                                       cellSize: CGSize(width: cellWidth, height: cellHeight))

        var body: [String] = []
        let background = svgHexColor(for: terminal.backgroundColor)
        body.append("<rect x=\"0\" y=\"0\" width=\"\(svgNumber(width))\" height=\"\(svgNumber(height))\" fill=\"\(background)\"/>")

        for row in 0..<rows {
            for col in 0..<cols {
                guard let charData = terminal.getCharData(col: col, row: row),
                      charData.width > 0 else {
                    continue
                }

                let attribute = charData.attribute
                let x = CGFloat(col) * cellWidth
                let y = CGFloat(row) * cellHeight
                let character = String(terminal.getCharacter(for: charData))
                if character.isEmpty || character == "\u{0}" {
                    continue
                }

                let backgroundColor = svgHexColor(for: attribute.bg, defaultColor: terminal.backgroundColor)
                if backgroundColor != background {
                    body.append("<rect x=\"\(svgNumber(x))\" y=\"\(svgNumber(y))\" width=\"\(svgNumber(cellWidth * CGFloat(max(Int(charData.width), 1))))\" height=\"\(svgNumber(cellHeight))\" fill=\"\(backgroundColor)\"/>")
                }

                let foregroundColor = svgHexColor(for: attribute.fg, defaultColor: terminal.foregroundColor)
                let escaped = svgEscapedText(character)
                let weight = attribute.style.contains(.bold) ? " font-weight=\"700\"" : ""
                let italic = attribute.style.contains(.italic) ? " font-style=\"italic\"" : ""
                let decoration = svgTextDecoration(for: attribute.style)
                body.append("<text x=\"\(svgNumber(x))\" y=\"\(svgNumber(y + baseline))\" fill=\"\(foregroundColor)\" font-family=\"\(svgEscapedAttribute(fontName))\" font-size=\"\(svgNumber(fontSize))\"\(weight)\(italic)\(decoration)>\(escaped)</text>")
            }
        }

        additionalContent?(context)
        if !context.body.isEmpty {
            body.append(context.body)
        }

        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(svgNumber(width))" height="\(svgNumber(height))" viewBox="0 0 \(svgNumber(width)) \(svgNumber(height))">
        \(body.joined(separator: "\n"))
        </svg>
        """
    }

    private func svgTextDecoration(for style: CharacterStyle) -> String {
        var decorations: [String] = []
        if style.contains(.underline) {
            decorations.append("underline")
        }
        if style.contains(.crossedOut) {
            decorations.append("line-through")
        }
        guard !decorations.isEmpty else {
            return ""
        }
        return " text-decoration=\"\(decorations.joined(separator: " "))\""
    }

    private func svgHexColor(for color: Attribute.Color, defaultColor: Color) -> String {
        switch color {
        case .trueColor(let red, let green, let blue):
            return svgHexColor(red: red, green: green, blue: blue)
        case .ansi256(let code):
            if Int(code) < colors.count, let color = colors[Int(code)] {
                return svgHexColor(for: color)
            }
            return svgHexColor(for: defaultColor)
        case .defaultColor, .defaultInvertedColor:
            return svgHexColor(for: defaultColor)
        }
    }

    private func svgHexColor(for color: Color) -> String {
        svgHexColor(red: UInt8(color.red >> 8),
                    green: UInt8(color.green >> 8),
                    blue: UInt8(color.blue >> 8))
    }

    private func svgHexColor(for color: TTColor) -> String {
        #if os(macOS)
        let resolved = color.usingColorSpace(.deviceRGB) ?? color
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif

        return svgHexColor(red: UInt8(max(0, min(255, red * 255))),
                           green: UInt8(max(0, min(255, green * 255))),
                           blue: UInt8(max(0, min(255, blue * 255))))
    }

    private func svgHexColor(red: UInt8, green: UInt8, blue: UInt8) -> String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func svgNumber(_ value: CGFloat) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.001 {
            return String(Int(rounded))
        }
        return String(format: "%.3f", Double(value))
    }

    private func svgEscapedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func svgEscapedAttribute(_ value: String) -> String {
        svgEscapedText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
#endif
