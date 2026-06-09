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
#if canImport(ImageIO)
import ImageIO
#endif
#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

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

                let backgroundColor = svgHexColor(for: charData.attribute.bg, defaultColor: terminal.backgroundColor)
                guard backgroundColor != background else {
                    continue
                }

                let x = CGFloat(col) * cellWidth
                let y = CGFloat(row) * cellHeight
                body.append("<rect x=\"\(svgNumber(x))\" y=\"\(svgNumber(y))\" width=\"\(svgNumber(cellWidth * CGFloat(max(Int(charData.width), 1))))\" height=\"\(svgNumber(cellHeight))\" fill=\"\(backgroundColor)\"/>")
            }
        }

        for row in 0..<rows {
            let bufferRow = terminal.displayBuffer.yDisp + row
            if let selectionColumns = selectedColumnsRange(row: bufferRow, cols: cols) {
                let x = CGFloat(selectionColumns.lowerBound) * cellWidth
                let y = CGFloat(row) * cellHeight
                let selectionWidth = CGFloat(selectionColumns.count) * cellWidth
                let selectionColor = svgHexColor(for: selectedTextBackgroundColor)
                body.append("<rect x=\"\(svgNumber(x))\" y=\"\(svgNumber(y))\" width=\"\(svgNumber(selectionWidth))\" height=\"\(svgNumber(cellHeight))\" fill=\"\(selectionColor)\"/>")
            }
        }

        for row in 0..<rows {
            var runText = ""
            var runX: CGFloat = 0
            var runEndColumn = 0
            var runForeground = ""
            var runWeight = ""
            var runItalic = ""
            var runDecoration = ""

            func flushTextRun() {
                guard !runText.isEmpty else {
                    return
                }
                let y = CGFloat(row) * cellHeight
                body.append(svgTextElement(x: runX,
                                           y: y + baseline,
                                           text: runText,
                                           fill: runForeground,
                                           fontName: fontName,
                                           fontSize: fontSize,
                                           weight: runWeight,
                                           italic: runItalic,
                                           decoration: runDecoration))
                runText = ""
            }

            for col in 0..<cols {
                guard let charData = terminal.getCharData(col: col, row: row),
                      charData.width > 0 else {
                    continue
                }

                let attribute = charData.attribute
                let x = CGFloat(col) * cellWidth
                let character = String(terminal.getCharacter(for: charData))
                if character.isEmpty || character == "\u{0}" {
                    flushTextRun()
                    continue
                }

                let foregroundColor = svgHexColor(for: attribute.fg, defaultColor: terminal.foregroundColor)
                let weight = attribute.style.contains(.bold) ? " font-weight=\"700\"" : ""
                let italic = attribute.style.contains(.italic) ? " font-style=\"italic\"" : ""
                let decoration = svgTextDecoration(for: attribute.style)

                let canAppend = !runText.isEmpty &&
                    runEndColumn == col &&
                    runForeground == foregroundColor &&
                    runWeight == weight &&
                    runItalic == italic &&
                    runDecoration == decoration

                if !canAppend {
                    flushTextRun()
                    runX = x
                    runForeground = foregroundColor
                    runWeight = weight
                    runItalic = italic
                    runDecoration = decoration
                }

                runText.append(character)
                runEndColumn = col + max(Int(charData.width), 1)
            }
            flushTextRun()
        }

        body.append(contentsOf: svgImagePlaceholderElements(cols: cols,
                                                            rows: rows,
                                                            cellWidth: cellWidth,
                                                            cellHeight: cellHeight,
                                                            fontName: fontName,
                                                            fontSize: fontSize))

        if let cursor = svgCursorElement(cols: cols, rows: rows, cellWidth: cellWidth, cellHeight: cellHeight) {
            body.append(cursor)
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

    private func svgImagePlaceholderElements(cols: Int,
                                             rows: Int,
                                             cellWidth: CGFloat,
                                             cellHeight: CGFloat,
                                             fontName: String,
                                             fontSize: CGFloat) -> [String] {
        var elements: [String] = []
        var emittedVirtualPlacements = Set<String>()
        let displayBuffer = terminal.displayBuffer
        let isAltBuffer = terminal.isDisplayBufferAlternate
        var virtualPlacementsByImageId: [UInt32: [KittyPlacementRecord]] = [:]
        if !terminal.kittyGraphicsState.placementsByKey.isEmpty {
            for record in terminal.kittyGraphicsState.placementsByKey.values where record.isVirtual && record.isAlternateBuffer == isAltBuffer {
                virtualPlacementsByImageId[record.imageId, default: []].append(record)
            }
        }

        for visibleRow in 0..<rows {
            guard let line = terminal.getLine(row: visibleRow) else {
                continue
            }

            let bufferRow = displayBuffer.yDisp + visibleRow
            let lineInfo = buildAttributedString(row: bufferRow, line: line, cols: cols)
            if let images = lineInfo.images {
                for basicImage in images {
                    guard let image = basicImage as? AppleImage else {
                        continue
                    }

                    let x = CGFloat(image.col) * cellWidth + CGFloat(image.kittyPixelOffsetX)
                    let y = CGFloat(visibleRow + 1) * cellHeight - CGFloat(image.pixelHeight) + CGFloat(image.kittyPixelOffsetY)
                    let rect = CGRect(x: x,
                                      y: y,
                                      width: CGFloat(image.pixelWidth),
                                      height: CGFloat(image.pixelHeight))
                    let imageLabel: String
                    if let imageId = image.kittyImageId {
                        imageLabel = "kitty image \(imageId)"
                    } else {
                        imageLabel = "terminal image"
                    }
                    if let dataURI = SwiftTermSVGExportSupport.imageDataURI(for: image.image) {
                        elements.append(svgImageElement(rect: rect,
                                                        label: imageLabel,
                                                        dataURI: dataURI))
                    } else {
                        elements.append(svgImagePlaceholderElement(rect: rect,
                                                                   label: imageLabel,
                                                                   fontName: fontName,
                                                                   fontSize: fontSize))
                    }
                }
            }

            for placeholder in lineInfo.kittyPlaceholders {
                guard let records = virtualPlacementsByImageId[placeholder.imageId] else {
                    continue
                }
                guard let record = records.first(where: { record in
                    if placeholder.placementId != 0 && record.placementId != placeholder.placementId {
                        return false
                    }
                    return record.cols > placeholder.placeholderCol &&
                        record.rows > placeholder.placeholderRow &&
                        record.cols > 0 &&
                        record.rows > 0
                }) else {
                    continue
                }

                let key = "\(placeholder.imageId)-\(record.placementId)-\(visibleRow - placeholder.placeholderRow)-\(placeholder.col - placeholder.placeholderCol)"
                guard emittedVirtualPlacements.insert(key).inserted else {
                    continue
                }

                let x = CGFloat(placeholder.col - placeholder.placeholderCol) * cellWidth + CGFloat(record.pixelOffsetX)
                let y = CGFloat(visibleRow - placeholder.placeholderRow) * cellHeight + CGFloat(record.pixelOffsetY)
                let rect = CGRect(x: x,
                                  y: y,
                                  width: CGFloat(record.cols) * cellWidth,
                                  height: CGFloat(record.rows) * cellHeight)
                let label = "kitty placeholder \(placeholder.imageId)"
                if let kittyImage = terminal.kittyGraphicsState.imagesById[placeholder.imageId],
                   let dataURI = SwiftTermSVGExportSupport.imageDataURI(for: kittyImage.payload) {
                    elements.append(svgImageElement(rect: rect,
                                                    label: label,
                                                    dataURI: dataURI))
                } else {
                    elements.append(svgImagePlaceholderElement(rect: rect,
                                                               label: label,
                                                               fontName: fontName,
                                                               fontSize: fontSize))
                }
            }
        }

        return elements
    }

    private func svgTextElement(x: CGFloat,
                                y: CGFloat,
                                text: String,
                                fill: String,
                                fontName: String,
                                fontSize: CGFloat,
                                weight: String,
                                italic: String,
                                decoration: String) -> String {
        "<text x=\"\(svgNumber(x))\" y=\"\(svgNumber(y))\" fill=\"\(fill)\" font-family=\"\(svgEscapedAttribute(fontName))\" font-size=\"\(svgNumber(fontSize))\"\(weight)\(italic)\(decoration) xml:space=\"preserve\">\(svgEscapedText(text))</text>"
    }

    private func svgImageElement(rect: CGRect, label: String, dataURI: String) -> String {
        guard rect.width > 0, rect.height > 0 else {
            return ""
        }
        return "<image data-swiftterm-image=\"\(svgEscapedAttribute(label))\" x=\"\(svgNumber(rect.minX))\" y=\"\(svgNumber(rect.minY))\" width=\"\(svgNumber(rect.width))\" height=\"\(svgNumber(rect.height))\" href=\"\(dataURI)\" preserveAspectRatio=\"none\"/>"
    }

    private func svgImagePlaceholderElement(rect: CGRect, label: String, fontName: String, fontSize: CGFloat) -> String {
        guard rect.width > 0, rect.height > 0 else {
            return ""
        }

        let color = "#66EAD8"
        let labelSize = max(8, min(fontSize, rect.height * 0.45))
        let labelX = rect.minX + 4
        let labelY = rect.minY + max(labelSize + 3, rect.height / 2)
        return """
        <g data-swiftterm-image-placeholder="\(svgEscapedAttribute(label))">
        <rect x="\(svgNumber(rect.minX))" y="\(svgNumber(rect.minY))" width="\(svgNumber(rect.width))" height="\(svgNumber(rect.height))" fill="\(color)" fill-opacity="0.08" stroke="\(color)" stroke-width="1" stroke-dasharray="4 3"/>
        <line x1="\(svgNumber(rect.minX))" y1="\(svgNumber(rect.minY))" x2="\(svgNumber(rect.maxX))" y2="\(svgNumber(rect.maxY))" stroke="\(color)" stroke-width="1" stroke-opacity="0.55"/>
        <line x1="\(svgNumber(rect.maxX))" y1="\(svgNumber(rect.minY))" x2="\(svgNumber(rect.minX))" y2="\(svgNumber(rect.maxY))" stroke="\(color)" stroke-width="1" stroke-opacity="0.55"/>
        <text x="\(svgNumber(labelX))" y="\(svgNumber(labelY))" fill="\(color)" font-family="\(svgEscapedAttribute(fontName))" font-size="\(svgNumber(labelSize))">\(svgEscapedText(label))</text>
        </g>
        """
    }

    private func svgCursorElement(cols: Int, rows: Int, cellWidth: CGFloat, cellHeight: CGFloat) -> String? {
        guard terminal.cursorHidden == false else {
            return nil
        }

        let location = terminal.getCursorLocation()
        guard location.x >= 0, location.x < cols, location.y >= 0, location.y < rows else {
            return nil
        }

        let x = CGFloat(location.x) * cellWidth
        let y = CGFloat(location.y) * cellHeight
        let color = svgHexColor(for: caretColor)
        let minimumStroke = max(min(cellWidth, cellHeight) * 0.12, 1)

        switch terminal.options.cursorStyle {
        case .blinkBlock, .steadyBlock:
            return "<rect x=\"\(svgNumber(x))\" y=\"\(svgNumber(y))\" width=\"\(svgNumber(cellWidth))\" height=\"\(svgNumber(cellHeight))\" fill=\"\(color)\" fill-opacity=\"0.55\"/>"
        case .blinkUnderline, .steadyUnderline:
            let height = min(max(minimumStroke, 2), cellHeight)
            return "<rect x=\"\(svgNumber(x))\" y=\"\(svgNumber(y + cellHeight - height))\" width=\"\(svgNumber(cellWidth))\" height=\"\(svgNumber(height))\" fill=\"\(color)\"/>"
        case .blinkBar, .steadyBar:
            let width = min(max(minimumStroke, 2), cellWidth)
            return "<rect x=\"\(svgNumber(x))\" y=\"\(svgNumber(y))\" width=\"\(svgNumber(width))\" height=\"\(svgNumber(cellHeight))\" fill=\"\(color)\"/>"
        }
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

enum SwiftTermSVGExportSupport {
    static func imageDataURI(for image: TTImage) -> String? {
        #if os(macOS)
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return pngDataURI(png)
        }

        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let png = pngData(from: cgImage) else {
            return nil
        }
        return pngDataURI(png)
        #else
        guard let png = image.pngData() else {
            return nil
        }
        return pngDataURI(png)
        #endif
    }

    static func imageDataURI(for payload: KittyGraphicsPayload) -> String? {
        switch payload {
        case .png(let data):
            return pngDataURI(data)
        case .rgba(let bytes, let width, let height):
            guard let png = pngDataFromRGBA(bytes: bytes, width: width, height: height) else {
                return nil
            }
            return pngDataURI(png)
        }
    }

    static func pngDataURI(_ data: Data) -> String {
        "data:image/png;base64,\(data.base64EncodedString())"
    }

    static func pngDataFromRGBA(bytes: [UInt8], width: Int, height: Int) -> Data? {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(bytes).subdata(in: 0..<(width * height * 4)) as CFData),
              let image = CGImage(width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bitsPerPixel: 32,
                                  bytesPerRow: width * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: true,
                                  intent: .defaultIntent) else {
            return nil
        }
        return pngData(from: image)
    }

    static func pngData(from image: CGImage) -> Data? {
        #if canImport(ImageIO)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
        #else
        return nil
        #endif
    }
}
#endif
