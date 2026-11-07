//
//  WindowManagerTests.swift
//  SwiftTerm — WINDOW_PLAN.md Phases 2 and 3 (twin of the SwiftTermGL suite) (window protocol, headless core)
//
//  Everything here runs without a GPU: routing, stacking, focus, probes,
//  replies and limits, driven through the same byte feed a host uses.
//

import Foundation
import Testing
@testable import SwiftTerm

private let esc = "\u{1b}"

private func vtg(_ body: String) -> String {
    "\(esc)_VTG;\(body)\(esc)\\"
}

private func bytes(_ text: String) -> ArraySlice<UInt8> {
    Array(text.utf8)[...]
}

/// A manager plus a root terminal, wired the way a host wires them.
private final class Rig {
    let root: Terminal
    let manager: VTGWindowManager
    var sent: [String] = []
    var errorEvents = false

    init() {
        root = TerminalTestHarness.makeTerminal(cols: 40, rows: 12).terminal
        manager = VTGWindowManager(cellSize: { (width: 8, height: 16) },
                                   send: { _ in },
                                   processRunning: { true })
        manager.send = { [unowned self] data in self.sent.append(String(decoding: data, as: UTF8.self)) }
        manager.reportsErrors = { [unowned self] in self.errorEvents }
    }

    func feed(_ text: String) {
        manager.feed(bytes(text)) { root.feed(buffer: $0) }
    }

    func text(_ terminal: Terminal, row: Int) -> String {
        guard let line = terminal.getLine(row: row) else { return "" }
        return (0..<terminal.cols).map { String(terminal.getCharacter(for: line[$0])) }
            .joined().replacingOccurrences(of: "\u{0}", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    func window(_ id: String) -> VTGWindow { manager.windows[id]! }
}

struct WindowRouterTests {
    @Test("3.11 / rule 5: with no window, a read comes back as the caller's own slice")
    func passThroughIsTheSameSlice() {
        let router = VTGWindowRouter()
        let input = Array("hello \(esc)[31mred\(esc)[0m \(vtg("rect,id=r,x=1,y=1,w=2,h=2"))".utf8)
        let slice = input[...]
        let segments = router.route(slice)
        #expect(segments.count == 1)
        guard case .bytes(let out, let target) = segments.first else {
            Issue.record("expected bytes")
            return
        }
        #expect(target == nil)
        #expect(out.startIndex == slice.startIndex && out.endIndex == slice.endIndex)
        out.withUnsafeBufferPointer { a in
            slice.withUnsafeBufferPointer { b in #expect(a.baseAddress == b.baseAddress, "no copy") }
        }
    }

    @Test("windowSelect splits the stream, and Page Mode's windowCanvas? passes through")
    func selectSplits() {
        let router = VTGWindowRouter()
        let input = "a" + vtg("windowSelect,id=w") + "b" + vtg("windowCanvas?") + vtg("windowSelect,id=root") + "c"
        let segments = router.route(bytes(input))
        var routed: [String: String] = [:]
        var commands: [String] = []
        for segment in segments {
            switch segment {
            case .bytes(let slice, let target):
                routed[target ?? "root", default: ""] += String(decoding: slice, as: UTF8.self)
            case .command(let command):
                commands.append(command.name)
            }
        }
        #expect(routed["root"] == "ac")
        #expect(routed["w"] == "b" + vtg("windowCanvas?"))
        #expect(commands == ["windowSelect", "windowSelect"])
    }

    @Test("3.3: a window command split at every byte boundary routes the same")
    func splitReads() {
        let input = Array(("x" + vtg("windowSelect,id=w") + "yz" + vtg("windowRaise,id=w") + "q").utf8)
        func collect(_ chunks: [ArraySlice<UInt8>]) -> (String, String, [String]) {
            let router = VTGWindowRouter()
            var root = "", window = ""
            var commands: [String] = []
            for chunk in chunks {
                for segment in router.route(chunk) {
                    switch segment {
                    case .bytes(let slice, let target):
                        if target == nil { root += String(decoding: slice, as: UTF8.self) }
                        else { window += String(decoding: slice, as: UTF8.self) }
                    case .command(let command):
                        commands.append(command.name)
                    }
                }
            }
            return (root, window, commands)
        }
        let whole = collect([input[...]])
        #expect(whole.0 == "x")
        #expect(whole.1 == "yzq")
        #expect(whole.2 == ["windowSelect", "windowRaise"])
        for cut in 1..<input.count {
            let pieces = collect([input[0..<cut], input[cut...]])
            #expect(pieces.0 == whole.0 && pieces.1 == whole.1 && pieces.2 == whole.2, "cut at \(cut)")
        }
    }

    @Test("A runaway window command is released, not held forever")
    func runawayIsReleased() {
        let router = VTGWindowRouter()
        let long = "\(esc)_VTG;windowCreate,title=" + String(repeating: "x", count: VTGWindowRouter.maximumHeldBytes + 10)
        let segments = router.route(bytes(long))
        #expect(segments.contains { if case .bytes = $0 { return true } else { return false } })
    }
}

struct WindowManagerTests {
    @Test("Text and VTG after windowSelect land in the window; the root is untouched")
    func routesToWindow() {
        let rig = Rig()
        rig.feed("root-before" + vtg("windowCreate,id=map,cols=20,rows=5,x=40,y=30,title=Map")
                 + vtg("windowSelect,id=map") + "inside"
                 + vtg("rect,id=box,x=1,y=1,w=10,h=10,fill=#ff0000")
                 + vtg("windowSelect,id=root") + " root-after")
        let map = rig.window("map")
        #expect(rig.text(map.surface.terminal, row: 0) == "inside")
        #expect(map.surface.session.controller.scene.primitives.map(\.id) == ["box"])
        #expect(rig.text(rig.root, row: 0) == "root-before root-after")
        #expect(map.frame == VTGWindowFrame(x: 40, y: 30, columns: 20, rows: 5, title: "Map"))
    }

    @Test("Raise, lower and order change the stack; hit testing finds the top window")
    func stacking() {
        let rig = Rig()
        rig.feed(vtg("windowCreate,id=a,cols=10,rows=4,x=0,y=0,border=0")
                 + vtg("windowCreate,id=b,cols=10,rows=4,x=40,y=16,border=0")
                 + vtg("windowCreate,id=c,cols=10,rows=4,x=200,y=0,border=0"))
        #expect(rig.manager.order == ["a", "b", "c"])
        // a covers 0…80 × 0…64; b covers 40…120 × 16…80. At (50, 20) both do.
        #expect(rig.manager.window(at: VTGPoint(x: 50, y: 20))?.window.id == "b")
        rig.feed(vtg("windowRaise,id=a"))
        #expect(rig.manager.order == ["b", "c", "a"])
        #expect(rig.manager.window(at: VTGPoint(x: 50, y: 20))?.window.id == "a")
        rig.feed(vtg("windowLower,id=c"))
        #expect(rig.manager.order == ["c", "b", "a"])
        rig.feed(vtg("windowOrder,ids=a|c"))
        #expect(rig.manager.order == ["b", "a", "c"])
        #expect(rig.manager.window(at: VTGPoint(x: 50, y: 20))?.contentPoint == VTGPoint(x: 50, y: 20))
        #expect(rig.manager.window(at: VTGPoint(x: 150, y: 100)) == nil)
    }

    @Test("Hidden windows are not drawn and not hit; showing brings them back")
    func hideShow() {
        let rig = Rig()
        rig.feed(vtg("windowCreate,id=a,cols=10,rows=4,border=0") + vtg("windowHide,id=a"))
        #expect(rig.manager.visibleWindows.isEmpty)
        #expect(rig.manager.window(at: VTGPoint(x: 1, y: 1)) == nil)
        rig.feed(vtg("windowShow,id=a"))
        #expect(rig.manager.visibleWindows.map(\.id) == ["a"])
    }

    @Test("Closing the selected window sends output back to the root")
    func closeSelected() {
        let rig = Rig()
        rig.feed(vtg("windowCreate,id=a,cols=10,rows=4") + vtg("windowSelect,id=a") + vtg("windowClose,id=a") + "back")
        #expect(rig.manager.windows.isEmpty)
        #expect(rig.text(rig.root, row: 0) == "back")
    }

    @Test("3.4: reset closes every window and returns routing to the root")
    func resetReturnsToRoot() {
        let rig = Rig()
        rig.feed(vtg("windowCreate,id=a,cols=10,rows=4") + vtg("windowSelect,id=a") + "lost")
        rig.manager.reset()
        rig.feed("found")
        #expect(rig.manager.windows.isEmpty && rig.manager.order.isEmpty)
        #expect(rig.text(rig.root, row: 0) == "found")
    }

    @Test("Selecting a window that does not exist keeps output on the root")
    func unknownSelect() {
        let rig = Rig()
        rig.feed(vtg("windowSelect,id=ghost") + "here")
        #expect(rig.text(rig.root, row: 0) == "here")
        #expect(rig.manager.selectedWindow == nil)
    }

    @Test("3.5: inside a window, canvas? and glyphSize? answer for the window, tagged")
    func probesArePerWindow() {
        let rig = Rig()
        rig.feed(vtg("windowCreate,id=w,cols=20,rows=5") + vtg("windowSelect,id=w")
                 + vtg("canvas?") + vtg("glyphSize?") + vtg("windowSelect,id=root"))
        #expect(rig.sent.contains(vtg("canvas,window=w,width=160,height=80")))
        #expect(rig.sent.contains { $0.hasPrefix("\(esc)_VTG;glyphSize,window=w,") })
    }

    @Test("3.7: VTG replies from a window carry window=<id>")
    func repliesAreTagged() {
        #expect(VTGWindowReplyTagger.tag(vtg("mouse,x=3,y=4"), window: "map") == vtg("mouse,window=map,x=3,y=4"))
        #expect(VTGWindowReplyTagger.tag(vtg("canvas?"), window: "m") == vtg("canvas?,window=m"))
        #expect(VTGWindowReplyTagger.tag("plain", window: "m") == "plain")
    }

    @Test("windows? reports the stack, focus and selection")
    func query() {
        let rig = Rig()
        rig.feed(vtg("windowCreate,id=a,cols=4,rows=2") + vtg("windowCreate,id=b,cols=4,rows=2")
                 + vtg("windowFocus,id=a") + vtg("windows?"))
        #expect(rig.sent.last == vtg("windows,order=a|b,focus=a,selected=root,max=16"))
    }

    @Test("3.8: limits — size, count, ids — refused, and reported only to a program that asked")
    func limits() {
        let rig = Rig()
        rig.feed(vtg("windowCreate,id=big,cols=501,rows=2"))
        rig.feed(vtg("windowCreate,id=root,cols=2,rows=2"))
        rig.feed(vtg("windowCreate,id=bad name,cols=2,rows=2"))
        #expect(rig.manager.windows.isEmpty)
        #expect(rig.sent.isEmpty, "no errorEvents, no reply")
        rig.errorEvents = true
        for index in 0..<VTGWindowManager.maximumWindows {
            rig.feed(vtg("windowCreate,id=w\(index),cols=2,rows=2"))
        }
        rig.feed(vtg("windowCreate,id=extra,cols=2,rows=2"))
        #expect(rig.manager.windows.count == VTGWindowManager.maximumWindows)
        #expect(rig.sent.last == vtg("windowRejected,command=windowCreate,id=extra,reason=limit"))
        rig.feed(vtg("windowCreate,id=w0,cols=2,rows=2"))
        #expect(rig.sent.last == vtg("windowRejected,command=windowCreate,id=w0,reason=exists"))
    }

    @Test("Resizing a window resizes its grid")
    func resize() {
        let rig = Rig()
        rig.feed(vtg("windowCreate,id=a,cols=10,rows=4") + vtg("windowResize,id=a,cols=30,rows=8"))
        #expect(rig.window("a").surface.terminal.cols == 30)
        #expect(rig.window("a").surface.terminal.rows == 8)
        #expect(rig.window("a").frame.columns == 30)
    }

    @Test("Layout: border and title bar wrap the content")
    func layout() {
        let frame = VTGWindowFrame(x: 10, y: 20, columns: 4, rows: 2, title: "T")
        let layout = frame.layout(cellWidth: 8, cellHeight: 16)
        #expect(layout.content == VTGLayerClip(x: 11, y: 37, width: 32, height: 32))
        #expect(layout.outer == VTGLayerClip(x: 10, y: 20, width: 34, height: 50))
        #expect(layout.titleBar == VTGLayerClip(x: 11, y: 21, width: 32, height: 16))
    }

    @Test("3.9: three windows, text and graphics in each, raised and closed")
    func endToEnd() {
        let rig = Rig()
        for (id, x) in [("a", 0), ("b", 60), ("c", 120)] {
            rig.feed(vtg("windowCreate,id=\(id),cols=8,rows=3,x=\(x),y=10")
                     + vtg("windowSelect,id=\(id)") + "win-\(id)"
                     + vtg("circle,id=dot,cx=4,cy=4,r=3,fill=#00ff00"))
        }
        rig.feed(vtg("windowSelect,id=root") + vtg("windowRaise,id=a") + vtg("windowClose,id=b"))
        #expect(rig.manager.order == ["c", "a"])
        #expect(rig.text(rig.window("a").surface.terminal, row: 0) == "win-a")
        #expect(rig.text(rig.window("c").surface.terminal, row: 0) == "win-c")
        #expect(rig.window("c").surface.session.controller.scene.primitives.map(\.id) == ["dot"])
        #expect(rig.text(rig.root, row: 0) == "")
    }

    @Test("2.6: windows are advertised only by a host that composites them")
    func advertisement() {
        let controller = VTGHostController()
        let canvas = VTGCanvasSize(width: 100, height: 100)
        let plain = controller.process([VectorTerminalGraphicsCommand(name: "capabilities?")], canvas: canvas)
        #expect(plain.first?.contains("windows=") == false)
        controller.advertisesWindows = true
        let windowed = controller.process([VectorTerminalGraphicsCommand(name: "capabilities?")], canvas: canvas)
        #expect(windowed.first?.contains(",windows=experimental,windowMax=16,windowText=1") == true)
    }
}

struct WindowMouseTests {
    @Test("3.6: a click over a window goes to that window's program, in its own coordinates")
    func clickRoutesToWindow() {
        var sent: [String] = []
        let manager = VTGWindowManager(cellSize: { (width: 8, height: 16) }, send: { sent.append(String(decoding: $0, as: UTF8.self)) },
                                       processRunning: { true })
        let root = TerminalTestHarness.makeTerminal(cols: 40, rows: 12).terminal
        let esc = "\u{1b}"
        func vtg(_ body: String) -> String { "\(esc)_VTG;\(body)\(esc)\\" }
        manager.feed(Array((vtg("windowCreate,id=w,cols=10,rows=4,x=100,y=50,border=0")
                            + vtg("windowSelect,id=w") + vtg("mouseEvents,enabled=1,mode=raw")
                            + vtg("windowSelect,id=root")).utf8)[...]) { root.feed(buffer: $0) }
        #expect(manager.handleMouse(type: .down, button: 0, at: VTGPoint(x: 120, y: 70), modifiers: ""))
        #expect(sent.last?.contains("mouse,window=w,") == true)
        #expect(sent.last?.contains("x=20,y=20") == true)
        #expect(!manager.handleMouse(type: .down, button: 0, at: VTGPoint(x: 5, y: 5), modifiers: ""), "root's")
    }
}

struct WindowFrameEventTests {
    @Test("windowEvents: a click on a title bar is reported, so the program can drag the window")
    func titleClick() {
        var sent: [String] = []
        let manager = VTGWindowManager(cellSize: { (width: 8, height: 16) },
                                       send: { sent.append(String(decoding: $0, as: UTF8.self)) },
                                       processRunning: { true })
        let esc = "\u{1b}"
        func vtg(_ body: String) -> String { "\(esc)_VTG;\(body)\(esc)\\" }
        manager.feed(Array((vtg("windowCreate,id=w,cols=10,rows=4,x=100,y=50,title=T")).utf8)[...]) { _ in }
        #expect(manager.handleMouse(type: .down, button: 0, at: VTGPoint(x: 120, y: 55), modifiers: ""))
        #expect(sent.isEmpty, "not asked for: nothing sent")
        manager.feed(Array(vtg("windowEvents,enabled=1").utf8)[...]) { _ in }
        manager.handleMouse(type: .down, button: 0, at: VTGPoint(x: 120, y: 55), modifiers: "")
        #expect(sent.last == vtg("windowMouse,id=w,part=title,type=down,button=0,x=120,y=55,modifiers="))
    }
}

struct WindowRouterScanTests {
    @Test("Both scans agree on every case, whichever one this build uses")
    func scansAgree() {
        let esc = "\u{1b}"
        let cases: [(String, Bool)] = [
            ("plain text", false),
            ("\(esc)[31mred\(esc)[0m", false),
            ("x\(esc)_VTG;rect,id=r\(esc)\\", false),
            ("x\(esc)_VTG;windowSelect,id=a\(esc)\\", true),
            (String(repeating: "\(esc)[0m", count: 40) + "\(esc)_VTG;window", true),
            ("tail \(esc)_VT", true),     // a split introducer
            ("tail \(esc)", true),
            ("tail \(esc)_VTX", false),
        ]
        for (text, expected) in cases {
            let bytes = Array(text.utf8)[...]
            #expect(VTGWindowRouter.scanWithSIMD(bytes) == expected, "SIMD: \(text.debugDescription)")
            #expect(VTGWindowRouter.scanWithMemchr(bytes) == expected, "memchr: \(text.debugDescription)")
        }
    }
}
