import XCTest
@testable import SwiftTerm
#if os(macOS)
import AppKit
#endif

#if os(macOS) || os(iOS) || os(visionOS)
final class SVGTerminalRendererTests: XCTestCase {
    func testPNGKittyPayloadUsesDataURIWithoutReencoding() {
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47])
        let uri = SwiftTermSVGExportSupport.imageDataURI(for: KittyGraphicsPayload.png(pngBytes))

        XCTAssertEqual(uri, "data:image/png;base64,\(pngBytes.base64EncodedString())")
    }

    func testRGBAPayloadConvertsToPNGDataURI() throws {
        let rgba: [UInt8] = [
            255, 0, 0, 255,
            0, 255, 0, 255,
            0, 0, 255, 255,
            255, 255, 255, 255
        ]

        let uri = try XCTUnwrap(SwiftTermSVGExportSupport.imageDataURI(for: KittyGraphicsPayload.rgba(bytes: rgba, width: 2, height: 2)))

        XCTAssertTrue(uri.hasPrefix("data:image/png;base64,"))
        let encoded = String(uri.dropFirst("data:image/png;base64,".count))
        let decoded = try XCTUnwrap(Data(base64Encoded: encoded))
        XCTAssertGreaterThan(decoded.count, 8)
        XCTAssertEqual(Array(decoded.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testInvalidRGBAPayloadReturnsNilForPlaceholderFallback() {
        let uri = SwiftTermSVGExportSupport.imageDataURI(for: KittyGraphicsPayload.rgba(bytes: [255, 0, 0], width: 1, height: 1))

        XCTAssertNil(uri)
    }

    #if os(macOS)
    @MainActor
    func testSVGSnapshotIncludesEscapedTextSelectionAndCursor() {
        let view = TerminalView(frame: CGRect(origin: .zero, size: CGSize(width: 800, height: 240)),
                                font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular))
        view.selectedTextBackgroundColor = NSColor(deviceRed: 0x11 / 255.0,
                                                   green: 0x22 / 255.0,
                                                   blue: 0x33 / 255.0,
                                                   alpha: 1)
        view.caretColor = NSColor(deviceRed: 0x44 / 255.0,
                                  green: 0x55 / 255.0,
                                  blue: 0x66 / 255.0,
                                  alpha: 1)
        view.terminal.options.cursorStyle = .steadyBar
        view.terminal.feed(text: "A&B <tag>\r\nsame same")
        view.terminal.feed(text: "\u{1b}[2;4H")
        view.selection.setSelection(start: Position(col: 0, row: 0),
                                    end: Position(col: 3, row: 0))

        let svg = view.makeSVGSnapshot()

        XCTAssertTrue(svg.contains("<svg xmlns=\"http://www.w3.org/2000/svg\""))
        XCTAssertTrue(svg.contains("A&amp;B &lt;tag&gt;"))
        XCTAssertTrue(svg.contains("xml:space=\"preserve\""))
        XCTAssertTrue(svg.contains("fill=\"#112233\""))
        XCTAssertTrue(svg.contains("fill=\"#445566\""))
        XCTAssertLessThan(svg.components(separatedBy: "<text ").count, 12)
    }
    #endif
}
#endif
