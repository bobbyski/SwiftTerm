//
//  VTGPageModeTests.swift
//
//  VTG Page Mode: an off-screen page floating above the terminal. The first
//  suite is the compatibility argument made mechanical — nothing changes for a
//  program that never sends `pageBegin`.
//

import Foundation
import Testing

@testable import SwiftTerm

private func vpm(
    _ name: String,
    _ parameters: [String: String] = [:],
    payload: String? = nil
) -> VectorTerminalGraphicsCommand {
    VectorTerminalGraphicsCommand(name: name, parameters: parameters, payload: payload)
}

private let canvas = VTGCanvasSize(width: 800, height: 600)
private let esc = "\u{1B}"

private func apc(_ body: String) -> String {
    "\(esc)_VTG;\(body)\(esc)\\"
}

/// A controller already in page mode with one open page, `p1`.
private func openController(_ open: [String: String] = ["id": "p1"]) -> VTGHostController {
    let controller = VTGHostController()
    _ = controller.process([vpm("pageBegin", ["id": "s"]), vpm("pageOpen", open)], canvas: canvas)
    return controller
}

@Suite("VTG Page Mode compatibility")
struct VTGPageModeCompatibilityTests {
    /// A host that predates page mode ignores every page command, because its
    /// scene reports unknown commands as unhandled and drops them.
    @Test func olderScenesIgnoreEveryPageCommand() {
        let scene = VTGGraphicsScene()
        scene.apply(vpm("rect", ["id": "r", "x": "1", "y": "1", "w": "5", "h": "5"]))
        let before = scene.primitives
        for name in VTGResponseEncoder.pageModeCommands {
            #expect(!scene.apply(vpm(name, ["id": "p"])), "\(name) was handled by a scene")
        }
        #expect(scene.primitives == before)
    }

    /// Without `pageBegin`, page commands are refused and drawing is untouched.
    @Test func pageCommandsWithoutPageBeginChangeNothing() {
        let controller = VTGHostController()
        let responses = controller.process([
            vpm("pageOpen", ["id": "p"]),
            vpm("rect", ["id": "r", "x": "0", "y": "0", "w": "10", "h": "10"])
        ], canvas: canvas)
        #expect(responses == [apc("pageRejected,id=p,command=pageOpen,reason=notInPageMode")])
        #expect(controller.scene.primitives.map(\.id) == ["r"])
        #expect(!controller.isPageModeActive)
    }

    /// The SDKs dispatch events with `contains("_VTG;resize")` and friends. A
    /// new event whose name began with one of those would be misparsed by every
    /// shipped build — as a window resize, say.
    @Test func noPageEventCollidesWithLegacyDispatch() {
        let controller = openController()
        var responses = controller.process([
            vpm("resizeEvents", ["enabled": "1"]),
            vpm("pageShow"),
            vpm("pageHide"),
            vpm("pageResize", ["w": "900", "h": "900"]),
            vpm("page?"),
            vpm("pageState?"),
            vpm("pageLimits?"),
            vpm("windowCanvas?"),
            vpm("fonts?"),
            vpm("textMeasure?", payload: "-:2:hi"),
            vpm("pageClose", ["id": "p1"]),
            vpm("pageEnd")
        ], canvas: canvas)
        responses.removeAll { $0.hasPrefix("\(esc)_VTG;resize,") }
        #expect(!responses.isEmpty)
        for response in responses {
            for legacy in ["_VTG;resize", "_VTG;canvas", "_VTG;size", "_VTG;mouse"] {
                #expect(!response.contains(legacy), "\(response) would dispatch as \(legacy)")
            }
        }
    }

    @Test func capabilitiesKeepTheirShapeAndAppendPageFeatures() {
        let response = VTGResponseEncoder.capabilities(canvas: canvas)
        #expect(response.contains(",colors=hex-rgb|hex-rgba,page=buffers2|layers|"))
        #expect(response.contains(",pageMaxLayers=32,text=style|styled|attr|box|measure|fonts\(esc)\\"))
        #expect(!response.contains("pageBegin"), "page commands stay out of the shared commands list")
        #expect(response.contains("version=1.6.0"))
    }

    @Test func advertisedPageCommandsAreAnswered() {
        for name in VTGResponseEncoder.pageModeCommands + ["textMeasure?", "fonts?"] {
            #expect(VTGHostController.extendedSessionCommands.contains(name), "\(name) is advertised but unhandled")
        }
        #expect(VTGHostController.extendedSessionCommands.count == VTGResponseEncoder.pageModeCommands.count + 2)
    }
}

@Suite("VTG Page Mode lifecycle")
struct VTGPageModeLifecycleTests {
    @Test func beginOpenShowEnd() {
        let controller = VTGHostController()
        let responses = controller.process([
            vpm("pageBegin", ["id": "demo"]),
            vpm("pageBegin", ["id": "again"]),
            vpm("pageOpen", ["id": "p1", "bg": "#101018"]),
            vpm("pageShow"),
            vpm("pageEnd")
        ], canvas: canvas)
        #expect(responses == [
            apc("pageBegan,id=demo,version=1,slots=2"),
            apc("pageRejected,id=again,command=pageBegin,reason=nested"),
            apc("pageOpened,id=p1,slot=A,w=800,h=600,growW=0,growH=1,replaced=none"),
            apc("pageShown,id=p1,slot=A"),
            apc("pageEnded,id=demo,reason=app")
        ])
        #expect(!controller.isPageModeActive)
    }

    @Test func openingIsOffScreenUntilShown() throws {
        let controller = openController()
        let mode = try #require(controller.pageMode)
        #expect(mode.visiblePage == nil)
        #expect(mode.targetPage?.id == "p1")
    }

    /// The two-buffer loop: one page on screen, one being built.
    @Test func pagesAlternateSlotsAroundTheVisibleOne() throws {
        let controller = openController()
        _ = controller.process([vpm("pageShow")], canvas: canvas)
        let second = controller.process([vpm("pageOpen", ["id": "p2"])], canvas: canvas)
        #expect(second == [apc("pageOpened,id=p2,slot=B,w=800,h=600,growW=0,growH=1,replaced=none")])
        let mode = try #require(controller.pageMode)
        #expect(mode.visiblePage?.id == "p1", "opening must not disturb what is on screen")
        #expect(mode.targetPage?.id == "p2")

        _ = controller.process([vpm("pageShow")], canvas: canvas)
        #expect(mode.visiblePage?.id == "p2")
        let third = controller.process([vpm("pageOpen", ["id": "p3"])], canvas: canvas)
        #expect(third == [apc("pageOpened,id=p3,slot=A,w=800,h=600,growW=0,growH=1,replaced=p1")])
        #expect(mode.visiblePage?.id == "p2")
    }

    @Test func showSelectAndHide() throws {
        let controller = openController()
        _ = controller.process([vpm("pageShow"), vpm("pageOpen", ["id": "p2"])], canvas: canvas)
        let mode = try #require(controller.pageMode)
        _ = controller.process([vpm("pageShow", ["id": "p1", "select": "1"])], canvas: canvas)
        #expect(mode.visiblePage?.id == "p1")
        #expect(mode.targetPage?.id == "p1")
        _ = controller.process([vpm("pageSelect", ["id": "p2"])], canvas: canvas)
        #expect(mode.visiblePage?.id == "p1")
        #expect(mode.targetPage?.id == "p2")
        let hidden = controller.process([vpm("pageHide")], canvas: canvas)
        #expect(hidden == [apc("pageHidden,id=p1")])
        #expect(mode.visiblePage == nil)
        #expect(controller.isPageModeActive)
    }

    @Test func closeFreesTheBuffer() throws {
        let controller = openController()
        let responses = controller.process([vpm("pageShow"), vpm("pageClose", ["id": "p1"])], canvas: canvas)
        #expect(responses.last == apc("pageClosed,id=p1"))
        let mode = try #require(controller.pageMode)
        #expect(mode.pages.isEmpty)
        #expect(mode.visiblePage == nil)
    }

    @Test func sizesComeFromPixelsCellsOrTheWindow() {
        let controller = VTGHostController()
        let responses = controller.process([
            vpm("pageBegin"),
            vpm("pageOpen", ["id": "px", "w": "1000", "h": "300"]),
            vpm("pageOpen", ["id": "cells", "cols": "10", "rows": "4"]),
            vpm("pageOpen", ["id": "grow", "w": "-1", "grow": "wh"]),
        ], canvas: canvas, glyphSize: (width: 8, height: 16))
        #expect(responses.contains(apc("pageOpened,id=px,slot=A,w=1000,h=300,growW=0,growH=0,replaced=none")))
        #expect(responses.contains(apc("pageOpened,id=cells,slot=B,w=80,h=64,growW=0,growH=0,replaced=none")))
        #expect(responses.contains(apc("pageOpened,id=grow,slot=A,w=800,h=600,growW=1,growH=1,replaced=px")))
    }

    @Test func teardownRoutesAllEndPageMode() {
        let muted = openController()
        muted.mute()
        #expect(!muted.isPageModeActive)

        let detached = openController()
        _ = detached.process([vpm("detach")], canvas: canvas)
        #expect(!detached.isPageModeActive)

        let reset = openController()
        reset.resetSession()
        #expect(!reset.isPageModeActive)

        let dismissed = openController()
        #expect(dismissed.dismissPageMode(reason: "promptMark", canvas: canvas) == [apc("pageEnded,id=s,reason=promptMark")])
        #expect(!dismissed.isPageModeActive)
    }
}

@Suite("VTG Page Mode drawing")
struct VTGPageModeDrawingTests {
    @Test func drawingGoesToThePageNotTheBaseScene() throws {
        let controller = openController()
        _ = controller.process([
            vpm("rect", ["id": "r", "x": "10", "y": "10", "w": "20", "h": "20"]),
            vpm("circle", ["id": "c", "cx": "50", "cy": "50", "r": "5", "layer": "3"])
        ], canvas: canvas)
        #expect(controller.scene.primitives.isEmpty)
        let page = try #require(controller.pageMode?.targetPage)
        #expect(page.orderedLayers.map(\.id) == ["1", "3"])
        #expect(page.layer(id: "1")?.scene.primitives.map(\.id) == ["r"])
        #expect(page.layer(id: "3")?.scene.primitives.map(\.id) == ["c"])
        #expect(page.layer(id: "3")?.z == 3)
    }

    @Test func pageTargetBaseSendsDrawingBack() throws {
        let controller = openController()
        _ = controller.process([
            vpm("pageTarget", ["scene": "base"]),
            vpm("line", ["id": "l", "x1": "0", "y1": "0", "x2": "5", "y2": "5"]),
            vpm("pageTarget", ["scene": "page"]),
            vpm("line", ["id": "m", "x1": "0", "y1": "0", "x2": "5", "y2": "5"])
        ], canvas: canvas)
        #expect(controller.scene.primitives.map(\.id) == ["l"])
        #expect(controller.pageMode?.targetPage?.layer(id: "1")?.scene.primitives.map(\.id) == ["m"])
    }

    @Test func drawingBeforeAnyPageIsRefused() {
        let controller = VTGHostController()
        let responses = controller.process([
            vpm("pageBegin", ["id": "s"]),
            vpm("rect", ["id": "r", "x": "0", "y": "0", "w": "1", "h": "1"])
        ], canvas: canvas)
        #expect(responses.last == apc("pageError,id=s,reason=noPage,command=rect"))
        #expect(controller.scene.primitives.isEmpty)
    }

    @Test func queriesAndSubscriptionsNeverCreateLayers() throws {
        let controller = openController()
        _ = controller.process([vpm("mouseEvents", ["enabled": "1"]), vpm("glyphSize?"), vpm("capabilities?")], canvas: canvas)
        #expect(controller.pageMode?.targetPage?.layers.isEmpty == true)
    }

    @Test func layerCommandsWork() throws {
        let controller = openController()
        _ = controller.process([
            vpm("pageLayerAdd", ["id": "bg", "z": "-5", "cache": "1"]),
            vpm("pageLayerAdd", ["id": "hud", "z": "10", "scroll": "fixed", "alpha": "0.5"]),
            vpm("pageLayerSelect", ["id": "bg"]),
            vpm("rect", ["id": "sky", "x": "0", "y": "0", "w": "100", "h": "100"]),
            vpm("pageLayerSelect", ["id": "hud"]),
            vpm("styledText", ["id": "score", "x": "4", "y": "4"], payload: "Score 10"),
            vpm("layer", ["id": "score", "layer": "bg"]),
            vpm("pageLayerOffset", ["id": "bg", "x": "-3", "y": "2"]),
            vpm("pageLayerVisible", ["id": "hud", "visible": "0"])
        ], canvas: canvas)
        let page = try #require(controller.pageMode?.targetPage)
        #expect(page.orderedLayers.map(\.id) == ["bg", "hud"])
        let bg = try #require(page.layer(id: "bg"))
        let hud = try #require(page.layer(id: "hud"))
        #expect(bg.cacheHint)
        #expect(bg.scene.primitives.map(\.id) == ["sky", "score"])
        #expect(bg.offset == VTGLayerOffset(x: -3, y: 2))
        #expect(hud.scrollMode == .fixed)
        #expect(hud.alpha == 0.5)
        #expect(!hud.isVisible)

        _ = controller.process([vpm("pageLayerClear", ["id": "bg"]), vpm("pageLayerRemove", ["id": "hud"])], canvas: canvas)
        #expect(bg.scene.primitives.isEmpty)
        #expect(page.layers.map(\.id) == ["bg"])
    }

    @Test func layerLimitIsReported() throws {
        let controller = openController()
        let commands = (0..<(VTGPage.maximumLayers + 1)).map { vpm("pageLayerAdd", ["id": "l\($0)"]) }
        let responses = controller.process(commands, canvas: canvas)
        #expect(responses.last == apc("pageError,id=p1,reason=limit,limit=layers"))
        #expect(controller.pageMode?.targetPage?.layers.count == VTGPage.maximumLayers)
    }

    @Test func spriteAssetsAreSharedAcrossLayers() throws {
        let controller = openController()
        _ = controller.process([
            vpm("vectorSpriteUpload", ["id": "ship", "width": "10", "height": "10"], payload: "M 0 0 L 10 10 Z"),
            vpm("sprite", ["id": "s1", "image": "ship", "x": "5", "y": "5", "layer": "2"]),
            vpm("pageLayerAdd", ["id": "late"])
        ], canvas: canvas)
        let page = try #require(controller.pageMode?.targetPage)
        #expect(page.layer(id: "2")?.scene.vectorSpriteAsset(id: "ship") != nil)
        #expect(page.layer(id: "late")?.scene.vectorSpriteAsset(id: "ship") != nil)
    }

    @Test func clearEmptiesThePageButKeepsBorrowedLayers() throws {
        let controller = openController()
        _ = controller.process([
            vpm("pageLayerAdd", ["id": "bg"]),
            vpm("rect", ["id": "sky", "x": "0", "y": "0", "w": "10", "h": "10", "layer": "bg"]),
            vpm("pageShow"),
            vpm("pageOpen", ["id": "p2"]),
            vpm("pageLayerCopy", ["id": "bg", "from": "p1", "layer": "bg"]),
            vpm("rect", ["id": "ship", "x": "0", "y": "0", "w": "10", "h": "10"]),
            vpm("clear")
        ], canvas: canvas)
        let page = try #require(controller.pageMode?.targetPage)
        #expect(page.layer(id: "1")?.scene.primitives.isEmpty == true)
        #expect(page.layer(id: "bg")?.scene.primitives.map(\.id) == ["sky"])
    }
}

@Suite("VTG Page Mode frames")
struct VTGPageModeFrameTests {
    /// A frame covers the page, because the page is what the program is
    /// drawing into.
    @Test func frameHidesPageDrawingUntilCommit() throws {
        let controller = openController()
        _ = controller.process([
            vpm("rect", ["id": "kept", "x": "0", "y": "0", "w": "10", "h": "10"]),
            vpm("pageShow")
        ], canvas: canvas)
        let visible = try #require(controller.pageMode?.visiblePage)

        _ = controller.process([
            vpm("startFrame", ["id": "f1"]),
            vpm("rect", ["id": "pending", "x": "20", "y": "20", "w": "10", "h": "10"]),
            vpm("pageLayerAdd", ["id": "late"])
        ], canvas: canvas)
        #expect(visible.layer(id: "1")?.scene.primitives.map(\.id) == ["kept"])
        #expect(visible.layer(id: "late") == nil)
        #expect(controller.activePageMode?.targetPage !== visible, "drawing goes to the frame's copy")

        _ = controller.process([vpm("endFrame", ["id": "f1"])], canvas: canvas)
        let committed = try #require(controller.pageMode?.visiblePage)
        #expect(committed.layer(id: "1")?.scene.primitives.map(\.id) == ["kept", "pending"])
        #expect(committed.layer(id: "late") != nil)
        #expect(controller.pageMode?.targetPage === committed)
    }

    @Test func cancelDiscardsPageDrawing() throws {
        let controller = openController()
        _ = controller.process([
            vpm("rect", ["id": "kept", "x": "0", "y": "0", "w": "10", "h": "10"]),
            vpm("pageShow"),
            vpm("startFrame", ["id": "f1"]),
            vpm("rect", ["id": "dropped", "x": "0", "y": "0", "w": "10", "h": "10"]),
            vpm("cancelFrame", ["id": "f1"])
        ], canvas: canvas)
        let page = try #require(controller.pageMode?.visiblePage)
        #expect(page.layer(id: "1")?.scene.primitives.map(\.id) == ["kept"])
        #expect(controller.pageMode?.targetPage === page)
    }

    @Test func timeoutDiscardsPageDrawingToo() throws {
        var currentDate = Date(timeIntervalSince1970: 0)
        let controller = VTGHostController(now: { currentDate })
        _ = controller.process([
            vpm("pageBegin", ["id": "s"]),
            vpm("pageOpen", ["id": "p1"]),
            vpm("rect", ["id": "kept", "x": "0", "y": "0", "w": "10", "h": "10"]),
            vpm("pageShow"),
            vpm("startFrame", ["id": "f1", "timeout": "10"]),
            vpm("rect", ["id": "dropped", "x": "0", "y": "0", "w": "10", "h": "10"])
        ], canvas: canvas)
        currentDate = currentDate.addingTimeInterval(1)
        let responses = controller.process([vpm("canvas?")], canvas: canvas)
        #expect(responses.first == apc("frameTimeout,id=f1,reason=timeout"))
        let page = try #require(controller.pageMode?.visiblePage)
        #expect(page.layer(id: "1")?.scene.primitives.map(\.id) == ["kept"])
    }

    /// Borrowed layers belong to their owner, so a frame does not copy them
    /// and the owner's drawing still shows through.
    @Test func borrowedLayersAreNotCopiedByAFrame() throws {
        let controller = openController()
        _ = controller.process([
            vpm("pageLayerAdd", ["id": "bg"]),
            vpm("rect", ["id": "sky", "x": "0", "y": "0", "w": "10", "h": "10", "layer": "bg"]),
            vpm("pageShow"),
            vpm("pageOpen", ["id": "p2"]),
            vpm("pageLayerCopy", ["id": "bg", "from": "p1", "layer": "bg"]),
            vpm("startFrame", ["id": "f1"])
        ], canvas: canvas)
        let framePage = try #require(controller.activePageMode?.targetPage)
        let owner = try #require(controller.pageMode?.page(id: "p1")?.layer(id: "bg"))
        #expect(framePage.layer(id: "bg")?.scene === owner.scene)
    }

    /// A frame covers page lifecycle too: a page opened, drawn, and shown
    /// inside one appears only when it commits.
    @Test func openingAndShowingInsideAFrameLandsAtCommit() throws {
        let controller = openController()
        _ = controller.process([
            vpm("rect", ["id": "first", "x": "0", "y": "0", "w": "10", "h": "10"]),
            vpm("pageShow"),
            vpm("startFrame", ["id": "f1"]),
            vpm("pageOpen", ["id": "p2"]),
            vpm("rect", ["id": "fresh", "x": "0", "y": "0", "w": "10", "h": "10"]),
            vpm("pageShow")
        ], canvas: canvas)
        #expect(controller.pageMode?.visiblePage?.id == "p1", "the new page is not on screen yet")
        #expect(controller.pageMode?.page(id: "p2") == nil)

        _ = controller.process([vpm("endFrame", ["id": "f1"])], canvas: canvas)
        let mode = try #require(controller.pageMode)
        #expect(mode.visiblePage?.id == "p2")
        #expect(mode.page(id: "p2")?.layer(id: "1")?.scene.primitives.map(\.id) == ["fresh"])
        #expect(mode.page(id: "p1")?.layer(id: "1")?.scene.primitives.map(\.id) == ["first"])
    }

    /// And a cancelled frame leaves no trace of any of it.
    @Test func cancellingUndoesPageLifecycleToo() throws {
        let controller = openController()
        _ = controller.process([
            vpm("pageShow"),
            vpm("startFrame", ["id": "f1"]),
            vpm("pageOpen", ["id": "p2"]),
            vpm("pageShow"),
            vpm("cancelFrame", ["id": "f1"])
        ], canvas: canvas)
        let mode = try #require(controller.pageMode)
        #expect(mode.visiblePage?.id == "p1")
        #expect(mode.page(id: "p2") == nil)
        #expect(mode.pages.map(\.id) == ["p1"])
    }
}

@Suite("VTG Page Mode growth")
struct VTGPageModeGrowthTests {
    @Test func growableHeightExtendsFixedWidthClips() throws {
        let controller = openController()
        let responses = controller.process([
            vpm("rect", ["id": "tall", "x": "10", "y": "1000", "w": "20", "h": "200"]),
            vpm("rect", ["id": "taller", "x": "10", "y": "1500", "w": "20", "h": "100"]),
            vpm("rect", ["id": "wide", "x": "2000", "y": "10", "w": "20", "h": "20"])
        ], canvas: canvas)
        let page = try #require(controller.pageMode?.targetPage)
        // A rect's stroke is at least 1px, and the page grows to fit the
        // stroke too: 1600 plus half a pixel.
        #expect(page.height == 1600.5)
        #expect(page.width == 800, "a fixed axis clips instead of growing")
        #expect(page.layer(id: "1")?.scene.primitives.map(\.id) == ["tall", "taller", "wide"], "clipped content stays retained")
        #expect(responses == [apc("pageGrew,id=p1,w=800,h=1600.50")], "growth is coalesced to one event per batch")
    }

    @Test func growthNeverShrinksAndHonoursPadding() throws {
        let controller = openController(["id": "p1", "padding": "16"])
        _ = controller.process([vpm("rect", ["id": "r", "x": "0", "y": "900", "w": "10", "h": "100"])], canvas: canvas)
        let page = try #require(controller.pageMode?.targetPage)
        #expect(page.height == 1016.5)
        _ = controller.process([vpm("rect", ["id": "r", "x": "0", "y": "0", "w": "10", "h": "10"])], canvas: canvas)
        #expect(page.height == 1016.5)
    }

    @Test func growthIsClampedAndReportedOnce() throws {
        let controller = openController(["id": "p1", "maxH": "1000"])
        let responses = controller.process([
            vpm("rect", ["id": "a", "x": "0", "y": "5000", "w": "10", "h": "10"]),
            vpm("rect", ["id": "b", "x": "0", "y": "6000", "w": "10", "h": "10"])
        ], canvas: canvas)
        #expect(controller.pageMode?.targetPage?.height == 1000)
        #expect(responses == [
            apc("pageError,id=p1,reason=limit,limit=h"),
            apc("pageGrew,id=p1,w=800,h=1000")
        ])
    }

    @Test func textBoxGrowsThePage() throws {
        let controller = openController()
        let paragraph = String(repeating: "Growth follows laid-out text, not a guess. ", count: 60)
        _ = controller.process([
            vpm("textBox", ["id": "body", "x": "20", "y": "500", "w": "200", "h": "-1", "size": "14"],
                payload: VTGTextRunParser.encode([("-", paragraph)]))
        ], canvas: canvas)
        let page = try #require(controller.pageMode?.targetPage)
        #expect(page.height > 600)
    }

    @Test func fixedLayersDoNotGrowThePage() throws {
        let controller = openController()
        _ = controller.process([
            vpm("pageLayerAdd", ["id": "hud", "scroll": "fixed"]),
            vpm("rect", ["id": "r", "x": "0", "y": "5000", "w": "10", "h": "10", "layer": "hud"])
        ], canvas: canvas)
        #expect(controller.pageMode?.targetPage?.height == 600)
    }
}

@Suite("VTG Page Mode shared layers")
struct VTGPageModeSharedLayerTests {
    private func twoPages() -> VTGHostController {
        let controller = openController()
        _ = controller.process([
            vpm("pageLayerAdd", ["id": "bg", "z": "0"]),
            vpm("rect", ["id": "sky", "x": "0", "y": "0", "w": "800", "h": "600", "layer": "bg"]),
            vpm("pageShow"),
            vpm("pageOpen", ["id": "p2"])
        ], canvas: canvas)
        return controller
    }

    @Test func referenceSharesTheSceneAndIsReadOnly() throws {
        let controller = twoPages()
        let responses = controller.process([
            vpm("pageLayerCopy", ["id": "bg", "from": "p1", "layer": "bg", "mode": "reference"]),
            vpm("rect", ["id": "nope", "x": "0", "y": "0", "w": "1", "h": "1", "layer": "bg"])
        ], canvas: canvas)
        #expect(responses == [apc("pageError,id=p2,reason=readOnlyLayer,layer=bg")])
        let mode = try #require(controller.pageMode)
        let owner = try #require(mode.page(id: "p1")?.layer(id: "bg"))
        let borrower = try #require(mode.page(id: "p2")?.layer(id: "bg"))
        #expect(borrower.scene === owner.scene)
        #expect(borrower.isReadOnly)

        // Drawing into the owner updates every borrower.
        _ = controller.process([
            vpm("pageSelect", ["id": "p1"]),
            vpm("circle", ["id": "sun", "cx": "10", "cy": "10", "r": "5", "layer": "bg"])
        ], canvas: canvas)
        #expect(borrower.scene.primitives.map(\.id) == ["sky", "sun"])
    }

    @Test func copyIsIndependent() throws {
        let controller = twoPages()
        _ = controller.process([
            vpm("pageLayerCopy", ["id": "bg", "from": "p1", "layer": "bg", "mode": "copy"]),
            vpm("rect", ["id": "mine", "x": "0", "y": "0", "w": "1", "h": "1", "layer": "bg"])
        ], canvas: canvas)
        let mode = try #require(controller.pageMode)
        #expect(mode.page(id: "p1")?.layer(id: "bg")?.scene.primitives.map(\.id) == ["sky"])
        #expect(mode.page(id: "p2")?.layer(id: "bg")?.scene.primitives.map(\.id) == ["sky", "mine"])
    }

    @Test func closingTheOwnerDetachesBorrowers() throws {
        let controller = twoPages()
        let responses = controller.process([
            vpm("pageLayerCopy", ["id": "bg", "from": "p1", "layer": "bg"]),
            vpm("pageClose", ["id": "p1"])
        ], canvas: canvas)
        #expect(responses == [
            apc("pageError,id=p2,reason=sourceClosed,layer=bg"),
            apc("pageClosed,id=p1")
        ])
        let borrower = try #require(controller.pageMode?.page(id: "p2")?.layer(id: "bg"))
        #expect(!borrower.isReadOnly)
        #expect(borrower.scene.primitives.map(\.id) == ["sky"], "the last content is kept")
    }
}

@Suite("VTG Page Mode size scope")
struct VTGPageModeSizeScopeTests {
    @Test func canvasReportsTheViewportAndWindowCanvasTheWindow() {
        let controller = openController()
        let responses = controller.process([
            vpm("pageViewport", ["x": "100", "y": "50", "w": "400", "h": "300"]),
            vpm("canvas?"),
            vpm("size?"),
            vpm("windowCanvas?")
        ], canvas: canvas)
        #expect(responses == [
            apc("canvas,width=400,height=300"),
            apc("size,width=400,height=300"),
            apc("windowCanvas,width=800,height=600")
        ])
    }

    /// A resize subscriber hears the viewport change, and hears the real window
    /// again before `pageEnded` — the restore that makes the change safe.
    @Test func resizeSubscribersAreResyncedOnExit() {
        let controller = VTGHostController()
        let responses = controller.process([
            vpm("resizeEvents", ["enabled": "1"]),
            vpm("pageBegin", ["id": "s"]),
            vpm("pageOpen", ["id": "p1"]),
            vpm("pageViewport", ["x": "0", "y": "0", "w": "400", "h": "300"]),
        ], canvas: canvas)
        #expect(responses == [
            apc("resize,width=800,height=600"),
            apc("pageBegan,id=s,version=1,slots=2"),
            apc("pageOpened,id=p1,slot=A,w=800,h=600,growW=0,growH=1,replaced=none"),
            apc("resize,width=400,height=300")
        ])
        let ended = controller.process([vpm("pageEnd")], canvas: canvas)
        #expect(ended == [
            apc("resize,width=800,height=600"),
            apc("pageEnded,id=s,reason=app")
        ])
        #expect(controller.process([vpm("canvas?")], canvas: canvas) == [apc("canvas,width=800,height=600")])
    }

    @Test func hostDismissalAlsoResyncs() {
        let controller = openController()
        _ = controller.process([vpm("resizeEvents", ["enabled": "1"])], canvas: canvas)
        #expect(controller.dismissPageMode(reason: "host", canvas: canvas) == [
            apc("resize,width=800,height=600"),
            apc("pageEnded,id=s,reason=host")
        ])
    }

    @Test func windowResizeFollowsAxesThatCameFromTheWindow() throws {
        let controller = openController()
        _ = controller.process([vpm("pageOpen", ["id": "fixed", "w": "300", "h": "200"])], canvas: canvas)
        let bigger = VTGCanvasSize(width: 1000, height: 700)
        let responses = controller.pageWindowResizeResponses(canvas: bigger)
        let mode = try #require(controller.pageMode)
        #expect(mode.page(id: "p1")?.width == 1000)
        #expect(mode.page(id: "p1")?.height == 700)
        #expect(mode.page(id: "fixed")?.width == 300)
        #expect(responses == [apc("pageResized,id=p1,w=1000,h=700,reason=window")])
    }
}

@Suite("VTG Page Mode input")
struct VTGPageModeInputTests {
    private func snapshot(_ x: Int, _ y: Int) -> VTGMouseSnapshot {
        VTGMouseSnapshot(x: x, y: y, cellX: 1, cellY: 1, modifiers: "none")
    }

    @Test func mouseEventsCarryPageCoordinatesAndPageHits() throws {
        let controller = openController(["id": "p1", "h": "2000"])
        _ = controller.process([
            vpm("mouseEvents", ["enabled": "1", "mode": "click"]),
            vpm("pageTarget", ["scene": "base"]),
            vpm("hit", ["id": "under", "x": "0", "y": "0", "w": "800", "h": "600", "target": "base"]),
            vpm("pageTarget", ["scene": "page"]),
            vpm("pageLayerAdd", ["id": "ui", "z": "5"]),
            vpm("hit", ["id": "button", "x": "100", "y": "1100", "w": "50", "h": "50", "layer": "ui", "target": "go"]),
            vpm("pageShow"),
            vpm("pageScroll", ["y": "1000"])
        ], canvas: canvas)

        let onButton = try #require(controller.mouseResponse(type: .click, button: 0, snapshot: snapshot(110, 110), canvas: canvas))
        #expect(onButton.contains(",hit=button,target=go,page=p1,pageX=110,pageY=1110,pageLayer=ui"))

        let elsewhere = try #require(controller.mouseResponse(type: .click, button: 0, snapshot: snapshot(400, 400), canvas: canvas))
        #expect(elsewhere.contains(",page=p1,pageX=400,pageY=1400"))
        #expect(elsewhere.contains("hit=under"), "base-scene hits still apply where the page has none")
        #expect(!elsewhere.contains("pageLayer="))
    }

    @Test func noPageFieldsWithoutAVisiblePage() throws {
        let controller = openController()
        _ = controller.process([vpm("mouseEvents", ["enabled": "1", "mode": "click"])], canvas: canvas)
        let response = try #require(controller.mouseResponse(type: .click, button: 0, snapshot: snapshot(5, 5), canvas: canvas))
        #expect(!response.contains("page="))
    }

    @Test func userScrollingIsOptInAndClamped() throws {
        let controller = openController(["id": "p1", "h": "1000"])
        _ = controller.process([vpm("pageShow")], canvas: canvas)
        #expect(controller.pageUserScrollResponse(at: VTGPoint(x: 10, y: 10), deltaX: 0, deltaY: -50, canvas: canvas) == nil)

        _ = controller.process([vpm("pageScrollMode", ["user": "1", "axis": "y"])], canvas: canvas)
        let scrolled = controller.pageUserScrollResponse(at: VTGPoint(x: 10, y: 10), deltaX: -30, deltaY: -50, canvas: canvas)
        #expect(scrolled == [apc("pageScrolled,id=p1,x=0,y=50,source=user")])
        let clamped = controller.pageUserScrollResponse(at: VTGPoint(x: 10, y: 10), deltaX: 0, deltaY: -5000, canvas: canvas)
        #expect(clamped == [apc("pageScrolled,id=p1,x=0,y=400,source=user")])
        #expect(controller.pageUserScrollResponse(at: VTGPoint(x: 10, y: 10), deltaX: 0, deltaY: -10, canvas: canvas) == [])
    }
}

@Suite("VTG Page Mode render plan")
struct VTGPageRenderPlanTests {
    /// The plan resolves scroll, layer offsets, clipping and alpha once, in
    /// canvas coordinates, for whichever backend draws it.
    @Test func planResolvesScrollOffsetsClipsAndAlpha() throws {
        let controller = openController(["id": "p1", "h": "2000", "bg": "#101018"])
        _ = controller.process([
            vpm("pageAlpha", ["alpha": "0.5"]),
            vpm("pageViewport", ["x": "100", "y": "50", "w": "400", "h": "300"]),
            vpm("pageLayerAdd", ["id": "body", "z": "0", "x": "10", "y": "5", "alpha": "0.5"]),
            vpm("rect", ["id": "r", "x": "0", "y": "0", "w": "50", "h": "50", "layer": "body"]),
            vpm("pageLayerAdd", ["id": "hud", "z": "9", "scroll": "fixed", "cache": "1"]),
            vpm("rect", ["id": "bar", "x": "0", "y": "0", "w": "50", "h": "10", "layer": "hud"]),
            vpm("pageScroll", ["y": "200"])
        ], canvas: canvas)
        let page = try #require(controller.pageMode?.targetPage)
        let plan = page.renderPlan(canvas: VTGRenderCanvas(width: 800, height: 600))

        #expect(plan.viewport == VTGLayerClip(x: 100, y: 50, width: 400, height: 300))
        // The page is taller than its window, so it fills it.
        #expect(plan.visibleRect == plan.viewport)
        #expect(plan.alpha == 0.5)
        #expect(plan.backgroundPlan?.entries.count == 1)

        let body = try #require(plan.layers.first { $0.layerID == "body" })
        // viewport origin - scroll + layer offset.
        #expect(body.offset == VTGLayerOffset(x: 110, y: -145))
        #expect(body.alpha == 0.25)
        #expect(!body.isCacheable)
        // The clip travels with the offset, so it is relative to it.
        let clip = try #require(body.plan.entries.first?.clip)
        #expect(clip.x == plan.viewport.x - body.offset.x)
        #expect(clip.y == plan.viewport.y - body.offset.y)
        #expect(body.plan.entries.first?.alpha == 0.25)

        let hud = try #require(plan.layers.first { $0.layerID == "hud" })
        #expect(hud.offset == VTGLayerOffset(x: 100, y: 50), "a fixed layer ignores the scroll")
        #expect(hud.isCacheable)
        #expect(plan.layers.map(\.layerID) == ["body", "hud"], "layers come in drawing order")
    }

    @Test func aPageScrolledOutOfViewPlansNothing() throws {
        let controller = openController(["id": "p1", "w": "200", "h": "200", "bg": "#101018"])
        _ = controller.process([
            vpm("pageViewport", ["x": "0", "y": "0", "w": "800", "h": "600"]),
            vpm("pageLayerAdd", ["id": "a"]),
            vpm("rect", ["id": "r", "x": "0", "y": "0", "w": "10", "h": "10", "layer": "a"])
        ], canvas: canvas)
        let page = try #require(controller.pageMode?.targetPage)
        page.scrollTo(x: 0, y: 0)
        var plan = page.renderPlan(canvas: VTGRenderCanvas(width: 800, height: 600))
        #expect(plan.visibleRect != nil)
        #expect(plan.layers.count == 1)

        page.scrollTo(x: 0, y: 5_000)
        plan = page.renderPlan(canvas: VTGRenderCanvas(width: 800, height: 600))
        #expect(plan.visibleRect == nil)
        #expect(plan.layers.isEmpty)
        #expect(plan.backgroundPlan == nil)
    }
}

@Suite("VTG Page Mode export")
struct VTGPageModeExportTests {
    @Test func svgShowsTheScrolledPage() throws {
        let controller = openController(["id": "p1", "h": "2000", "bg": "#000000"])
        _ = controller.process([
            vpm("rect", ["id": "r", "x": "0", "y": "1000", "w": "10", "h": "10"]),
            vpm("pageScroll", ["y": "900"])
        ], canvas: canvas)
        let page = try #require(controller.pageMode?.targetPage)
        let svg = page.makeSVGFragment(canvasWidth: 800, canvasHeight: 600)
        #expect(svg.contains("data-vtg-page=\"p1\""))
        #expect(svg.contains("translate(0 -900)"))
        #expect(svg.contains("fill=\"#000000\""))
    }
}
