//
//  VTGRichTextTests.swift
//
//  textStyle, styledText, attrText, textBox, and the length-prefixed run
//  encoding they share.
//

import Foundation
import Testing

@testable import SwiftTerm

private func textCommand(
    _ name: String,
    _ parameters: [String: String] = [:],
    payload: String? = nil
) -> VectorTerminalGraphicsCommand {
    VectorTerminalGraphicsCommand(name: name, parameters: parameters, payload: payload)
}

@Suite("VTG text run encoding")
struct VTGTextRunParserTests {
    @Test func decodesRunsBreaksAndBaseStyle() throws {
        let runs = try #require(VTGTextRunParser.parse("h1:9:Chapter 1NL:0:-:5:a;b,c"))
        #expect(runs.map(\.styleRef) == ["h1", "NL", "-"])
        #expect(runs.map(\.text) == ["Chapter 1", "", "a;b,c"])
        #expect(runs[1].isLineBreak)
        #expect(runs[2].usesBaseStyle)
    }

    @Test func lengthsCountUTF8Bytes() throws {
        let payload = VTGTextRunParser.encode([("b", "café"), ("-", "🙂 ok")])
        #expect(payload == "b:5:café-:7:🙂 ok")
        let runs = try #require(VTGTextRunParser.parse(payload))
        #expect(runs.map(\.text) == ["café", "🙂 ok"])
    }

    @Test func emptyPayloadIsNoRuns() {
        #expect(VTGTextRunParser.parse("") == [])
    }

    @Test(arguments: [
        "b:10:short",           // length past the end
        "b:x:abc",              // non-numeric length
        "b 1:1:a",              // invalid style reference
        "NL:1:x",               // a break carrying text
        "b:3:a\u{7}b",          // a control byte in run text
        "b:2:ab-",              // trailing garbage
        "b:-1:a"                // negative length
    ])
    func malformedPayloadsYieldNothing(_ payload: String) {
        #expect(VTGTextRunParser.parse(payload) == nil)
    }
}

@Suite("VTG rich text scene")
struct VTGRichTextSceneTests {
    @Test func stylesCascadeAndResolveAtDrawTime() throws {
        let scene = VTGGraphicsScene()
        scene.apply(textCommand("textStyle", ["id": "base", "font": "serif", "size": "20", "color": "#ffffff"]))
        scene.apply(textCommand("textStyle", ["id": "em", "inherit": "base", "slant": "italic", "weight": "bold"]))
        scene.apply(textCommand("attrText", ["id": "t", "x": "10", "y": "20", "style": "base"],
                                payload: "-:3:oneem:3:twoNL:0:nope:1:x"))

        guard case .richText(let text) = try #require(scene.primitives.first) else {
            Issue.record("expected rich text")
            return
        }
        #expect(text.kind == .attributed)
        #expect(text.runs.count == 4)
        #expect(text.runs[0].style.font == "serif")
        #expect(text.runs[0].style.italic == nil)
        #expect(text.runs[1].style.italic == true)
        #expect(text.runs[1].style.weight == 700)
        #expect(text.runs[1].style.size == 20)
        #expect(text.runs[2].isLineBreak)
        // An undefined style falls back to the base.
        #expect(text.runs[3].style == text.runs[0].style)

        // Redefining a style does not repaint text already drawn with it.
        scene.apply(textCommand("textStyle", ["id": "em", "color": "#ff0000"]))
        guard case .richText(let unchanged) = scene.primitives[0] else { return }
        #expect(unchanged.runs[1].style.italic == true)
    }

    @Test func styledTextTakesInlineAttributes() throws {
        let scene = VTGGraphicsScene()
        scene.apply(textCommand("styledText", ["id": "s", "x": "5", "y": "6", "size": "32", "weight": "600", "color": "#112233"],
                                payload: "Hello, VTG; world"))
        guard case .richText(let text) = try #require(scene.primitives.first) else { return }
        #expect(text.kind == .styled)
        #expect(text.plainText == "Hello, VTG; world")
        #expect(text.runs.first?.style.size == 32)
        #expect(text.runs.first?.style.weight == 600)
        #expect(text.baseline == .top)
        #expect(text.wrap == .none)
    }

    @Test func textBoxGrowsWhenHeightIsMinusOneOrMissing() throws {
        let scene = VTGGraphicsScene()
        scene.apply(textCommand("textBox", ["id": "a", "x": "0", "y": "0", "w": "100", "h": "-1", "inset": "4|8"], payload: "-:1:x"))
        scene.apply(textCommand("textBox", ["id": "b", "x": "0", "y": "0", "w": "100"], payload: "-:1:x"))
        scene.apply(textCommand("textBox", ["id": "c", "x": "0", "y": "0", "w": "100", "h": "40", "overflow": "ellipsis"], payload: "-:1:x"))
        let texts = scene.primitives.compactMap { primitive -> VTGRichText? in
            if case .richText(let text) = primitive { return text }
            return nil
        }
        #expect(texts.map(\.overflow) == [.grow, .grow, .ellipsis])
        #expect(texts[0].height == nil)
        #expect(texts[0].insets == VTGTextInsets(top: 4, right: 8, bottom: 4, left: 8))
        #expect(texts[2].height == 40)
    }

    @Test func malformedRunsCreateNoPrimitive() {
        let scene = VTGGraphicsScene()
        scene.apply(textCommand("attrText", ["id": "bad", "x": "0", "y": "0"], payload: "-:99:short"))
        #expect(scene.primitives.isEmpty)
    }

    @Test func clearKeepsStylesButResetForgetsThem() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 640, height: 480)
        _ = controller.process([textCommand("textStyle", ["id": "h", "size": "30"]), textCommand("clear")], canvas: canvas)
        #expect(controller.scene.textStyles.style(named: "h")?.size == 30)
        controller.resetSession()
        #expect(controller.scene.textStyles.style(named: "h") == nil)
    }

    @Test func richTextCommandsAreHandledByTheSceneOrController() {
        let scene = VTGGraphicsScene()
        for name in ["textStyle", "styledText", "attrText", "textBox"] {
            #expect(scene.apply(textCommand(name)), "\(name) is not handled by the scene")
        }
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 640, height: 480)
        for name in ["textMeasure?", "fonts?"] {
            let responses = controller.process([textCommand(name, payload: "")], canvas: canvas)
            #expect(responses.count == 1, "\(name) was not answered")
        }
    }

    @Test func baseTextPrimitiveIsUnchanged() throws {
        let scene = VTGGraphicsScene()
        scene.apply(textCommand("text", ["id": "t", "x": "1", "y": "2", "size": "16"], payload: "plain"))
        guard case .text(_, let x, let y, let value, _, let size) = try #require(scene.primitives.first) else {
            Issue.record("the original text primitive changed shape")
            return
        }
        #expect((x, y, value, size) == (1, 2, "plain", 16))
    }
}

#if canImport(CoreText)
@Suite("VTG rich text layout")
struct VTGRichTextLayoutTests {
    private func box(_ parameters: [String: String], _ text: String) throws -> VTGRichText {
        let scene = VTGGraphicsScene()
        scene.apply(textCommand("textBox", parameters.merging(["id": "b"]) { a, _ in a },
                                payload: VTGTextRunParser.encode([("-", text)])))
        guard case .richText(let rich) = try #require(scene.primitives.first) else {
            throw CancellationError()
        }
        return rich
    }

    private let paragraph = String(repeating: "The page is a document, not a window. ", count: 8)

    @Test func narrowBoxWraps() throws {
        let text = try box(["x": "10", "y": "20", "w": "120", "size": "14"], paragraph)
        let metrics = VTGTextLayout.metrics(for: text)
        #expect(metrics.lineCount > 4)
        #expect(metrics.x == 10)
        #expect(metrics.y == 20)
        #expect(metrics.width == 120)
        #expect(metrics.height > 14 * 4)
        #expect(!metrics.truncated)
    }

    @Test func clippedAndEllipsizedBoxesReportTruncation() throws {
        let clipped = try box(["x": "0", "y": "0", "w": "120", "h": "40", "size": "14"], paragraph)
        let ellipsis = try box(["x": "0", "y": "0", "w": "120", "h": "40", "size": "14", "overflow": "ellipsis"], paragraph)
        for text in [clipped, ellipsis] {
            let metrics = VTGTextLayout.metrics(for: text)
            #expect(metrics.truncated)
            #expect(metrics.height == 40)
            #expect(metrics.lineCount >= 1)
        }
    }

    @Test func alignmentMovesTheAnchor() {
        let run = VTGTextRun(text: "Centered", style: VTGTextStyle(size: 20))
        let left = VTGRichText(id: "l", kind: .styled, x: 200, y: 50, runs: [run], wrap: .none)
        var center = left
        center.alignment = .center
        var right = left
        right.alignment = .right
        let width = VTGTextLayout.metrics(for: left).width
        #expect(width > 0)
        #expect(abs(VTGTextLayout.metrics(for: center).x - (200 - width / 2)) < 0.5)
        #expect(abs(VTGTextLayout.metrics(for: right).x - (200 - width)) < 0.5)
    }

    @Test func alphabeticBaselinePutsTheFirstBaselineAtY() {
        let run = VTGTextRun(text: "Baseline", style: VTGTextStyle(size: 24))
        let text = VTGRichText(id: "b", kind: .styled, x: 0, y: 100, runs: [run], baseline: .alphabetic, wrap: .none)
        let metrics = VTGTextLayout.metrics(for: text)
        #expect(abs(metrics.y + metrics.firstBaseline - 100) < 0.5)
    }

    @Test func measurementMatchesThePrimitiveBounds() throws {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 640, height: 480)
        let payload = VTGTextRunParser.encode([("-", paragraph)])
        let responses = controller.process([
            textCommand("textMeasure?", ["id": "q", "w": "200", "size": "13"], payload: payload)
        ], canvas: canvas)
        let text = try box(["x": "0", "y": "0", "w": "200", "size": "13"], paragraph)
        let metrics = VTGTextLayout.metrics(for: text)
        let response = try #require(responses.first)
        #expect(response.hasPrefix("\u{1B}_VTG;textMeasure,id=q,"))
        #expect(response.contains("w=200,"))
        #expect(response.contains("lines=\(metrics.lineCount),"))
        #expect(response.contains("h=\(VTGHostController.pageNumber(metrics.height)),"))
    }

    @Test func svgExportCarriesStyledRuns() {
        let scene = VTGGraphicsScene()
        scene.apply(textCommand("textStyle", ["id": "b", "weight": "bold", "color": "#ff0000"]))
        scene.apply(textCommand("attrText", ["id": "t", "x": "10", "y": "10", "size": "18"],
                                payload: "-:4:One b:3:Two"))
        let svg = scene.makeSVGFragment()
        #expect(svg.contains("data-vtg-text=\"attrText\""))
        #expect(svg.contains(">One </tspan>"))
        #expect(svg.contains("font-weight=\"700\""))
        #expect(svg.contains("fill=\"#ff0000\""))
    }
}
#endif
