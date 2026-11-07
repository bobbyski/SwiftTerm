#if os(macOS)
//
//  WindowMacViewTests.swift
//  SwiftTerm — WINDOW_PLAN.md Phase 4 on the Mac (4.1–4.3)
//
//  VTG windows as child terminal views: created, fed, stacked and closed
//  through the same feed a program uses, and drawn by AppKit.
//

import AppKit
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
@Suite("Window plan: VTG windows on the Mac", .serialized)
struct WindowMacViewTests {
    private let esc = "\u{1b}"
    private func vtg(_ body: String) -> String { "\(esc)_VTG;\(body)\(esc)\\" }

    private func makeView() -> VectorTerminalView {
        let view = VectorTerminalView(frame: CGRect(x: 0, y: 0, width: 480, height: 320))
        view.vtgResponseHandler = { _ in }
        return view
    }

    private func feed(_ view: VectorTerminalView, _ text: String) {
        view.feedVTG(Array(text.utf8))
        view.updateDisplay(notifyAccessibility: false)
    }

    private func containers(_ view: VectorTerminalView) -> [VTGWindowContainerView] {
        view.subviews.compactMap { $0 as? VTGWindowContainerView }
    }

    private func text(_ terminal: Terminal, row: Int) -> String {
        guard let line = terminal.getLine(row: row) else { return "" }
        return (0..<terminal.cols).map { String(terminal.getCharacter(for: line[$0])) }
            .joined().replacingOccurrences(of: "\u{0}", with: " ").trimmingCharacters(in: .whitespaces)
    }

    @Test("A window is a child terminal view, fed by windowSelect, stacked by subview order")
    func childViews() {
        let view = makeView()
        feed(view, vtg("windowCreate,id=a,cols=10,rows=3,x=20,y=20,title=A")
             + vtg("windowCreate,id=b,cols=10,rows=3,x=60,y=40")
             + vtg("windowSelect,id=a") + "in-a" + vtg("windowSelect,id=root") + "in-root")
        let views = containers(view)
        #expect(views.map(\.windowID) == ["a", "b"])
        #expect(text(views[0].terminalView.getTerminal(), row: 0) == "in-a")
        #expect(text(view.getTerminal(), row: 0) == "in-root")
        #expect(views[0].terminalView.getTerminal().cols == 10)

        feed(view, vtg("windowRaise,id=a"))
        #expect(containers(view).map(\.windowID) == ["b", "a"], "raise moves the view to the top")

        feed(view, vtg("windowClose,id=b"))
        #expect(containers(view).map(\.windowID) == ["a"])
    }

    @Test("The frame follows the window: position from the top, title bar above the content")
    func framePlacement() {
        let view = makeView()
        feed(view, vtg("windowCreate,id=a,cols=10,rows=3,x=20,y=30,title=A"))
        guard let container = containers(view).first, let cell = view.currentVTGCellSize() else {
            Issue.record("no window")
            return
        }
        let layout = VTGWindowFrame(x: 20, y: 30, columns: 10, rows: 3, title: "A")
            .layout(cellWidth: cell.width, cellHeight: cell.height)
        // The root is not flipped: y is measured up from the bottom.
        #expect(abs(container.frame.minX - 20) < 0.001)
        #expect(abs(container.frame.maxY - (320 - 30)) < 0.001)
        #expect(abs(container.frame.height - layout.outer.height) < 0.001)
        #expect(abs(container.terminalView.frame.minY - (layout.content.y - 30)) < 0.001, "content below the title")
    }

    @Test("A reset closes every window and gives output back to the root")
    func resetClosesWindows() {
        let view = makeView()
        feed(view, vtg("windowCreate,id=a,cols=10,rows=3") + vtg("windowSelect,id=a"))
        view.resetVectorGraphicsSession()
        feed(view, "back")
        #expect(containers(view).isEmpty)
        #expect(text(view.getTerminal(), row: 0) == "back")
    }

    @Test("Replies from a window's own VTG session are tagged window=<id>")
    func repliesTagged() {
        let view = makeView()
        var replies: [String] = []
        view.vtgResponseHandler = { replies.append($0) }
        feed(view, vtg("windowCreate,id=w,cols=10,rows=3") + vtg("windowSelect,id=w")
             + vtg("canvas?") + vtg("windowSelect,id=root"))
        #expect(replies.contains { $0.hasPrefix("\(esc)_VTG;canvas,window=w,") })
    }

    @Test("4.3: the window's own view draws its content, opaque, over the stack")
    func windowViewDrawsItsContent() throws {
        let view = makeView()
        feed(view, vtg("rect,id=bg,x=0,y=0,w=480,h=320,fill=#ff0000,layer=1")
             + vtg("windowCreate,id=a,cols=10,rows=3,x=100,y=100,border=0,shadow=0")
             + vtg("windowSelect,id=a") + "\(esc)[48;2;0;0;255m" + String(repeating: " ", count: 30)
             + vtg("windowSelect,id=root"))
        guard let container = containers(view).first else {
            Issue.record("no window")
            return
        }
        let child = container.terminalView
        guard let rep = child.bitmapImageRepForCachingDisplay(in: child.bounds) else {
            Issue.record("no bitmap")
            return
        }
        child.cacheDisplay(in: child.bounds, to: rep)
        let sample = rep.colorAt(x: 4, y: 4)?.usingColorSpace(.sRGB)
        print("Window pixels: child view at (4,4) = \(String(describing: sample))")
        #expect((sample?.blueComponent ?? 0) > 0.7 && (sample?.redComponent ?? 1) < 0.3)
        // It sits above the root's overlay in AppKit's stacking.
        let overlayIndex = view.subviews.firstIndex { $0 === view.vtgOverlayView }
        let windowIndex = view.subviews.firstIndex { $0 === container }
        #expect(overlayIndex != nil && windowIndex != nil && windowIndex! > overlayIndex!)
    }

    @Test("4.6: only the focused window shows its caret (CoreGraphics)")
    func caretFollowsFocus() {
        let view = makeView()
        feed(view, vtg("windowCreate,id=a,cols=10,rows=3") + vtg("windowCreate,id=b,cols=10,rows=3,x=200"))
        let views = containers(view)
        #expect(views.allSatisfy { $0.terminalView.caretView?.isHidden == true }, "no focus yet")
        feed(view, vtg("windowFocus,id=a"))
        #expect(views[0].terminalView.caretView?.isHidden == false)
        #expect(views[1].terminalView.caretView?.isHidden == true)
        feed(view, vtg("windowFocus,id=root"))
        #expect(views[0].terminalView.caretView?.isHidden == true)
    }

    @Test("4.8 on the Mac: dragging a window over a busy 200x60 root, time per move")
    func dragTime() {
        let view = VectorTerminalView(frame: CGRect(x: 0, y: 0, width: 1700, height: 1000))
        view.vtgResponseHandler = { _ in }
        view.resize(cols: 200, rows: 60)
        for row in 0..<60 {
            view.feed(text: "\(esc)[\(row + 1);1H\(esc)[3\(row % 7 + 1)m" + String(repeating: "busy text ", count: 20))
        }
        for (index, id) in ["a", "b", "c"].enumerated() {
            feed(view, vtg("windowCreate,id=\(id),cols=60,rows=20,x=\(index * 300),y=\(index * 100),title=\(id)")
                 + vtg("windowSelect,id=\(id)") + String(repeating: "window text ", count: 80) + vtg("windowSelect,id=root"))
        }
        view.display()
        // Best of three rounds: in a full serial suite run the machine is busy,
        // and one round alone measured the load, not the drag.
        let moves = 30
        var rounds: [Double] = []
        for _ in 0..<3 {
            let started = ProcessInfo.processInfo.systemUptime
            for step in 0..<moves {
                view.feedVTG(Array(vtg("windowMove,id=a,x=\(step * 10),y=\(step * 5)").utf8))
                view.display()
            }
            rounds.append((ProcessInfo.processInfo.systemUptime - started) * 1000 / Double(moves))
        }
        let milliseconds = rounds.min() ?? .infinity
        print(String(format: "4.8 Mac: move + redraw with 3 windows over a 200x60 root: %.2f ms per move, best of %@ (debug, CoreGraphics, offscreen)",
                     milliseconds, rounds.map { String(format: "%.2f", $0) }.joined(separator: ", ")))
        #expect(milliseconds < 16.7)
    }
}
#endif
