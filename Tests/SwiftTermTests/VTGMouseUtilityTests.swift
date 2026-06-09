import Foundation
import Testing
#if os(macOS)
import AppKit
#endif

@testable import SwiftTerm

final class VTGMouseUtilityTests {
    @Test func clickSynthesizerRequiresSameButtonAndSmallMovement() {
        let synthesizer = VTGMouseClickSynthesizer(
            maximumClickInterval: 0.5,
            maximumClickDistance: 8
        )
        let down = VTGMouseSnapshot(x: 20, y: 30, cellX: 2, cellY: 3, modifiers: "none")
        let nearby = VTGMouseSnapshot(x: 24, y: 35, cellX: 2, cellY: 3, modifiers: "none")
        let farAway = VTGMouseSnapshot(x: 60, y: 80, cellX: 6, cellY: 8, modifiers: "none")

        synthesizer.recordDown(button: 0, snapshot: down, timestamp: 10)

        #expect(synthesizer.shouldSynthesizeClick(button: 0, snapshot: nearby, timestamp: 10.2))
        #expect(!synthesizer.shouldSynthesizeClick(button: 1, snapshot: nearby, timestamp: 10.2))
        #expect(!synthesizer.shouldSynthesizeClick(button: 0, snapshot: nearby, timestamp: 11))
        #expect(!synthesizer.shouldSynthesizeClick(button: 0, snapshot: farAway, timestamp: 10.2))

        synthesizer.reset()
        #expect(!synthesizer.shouldSynthesizeClick(button: 0, snapshot: nearby, timestamp: 10.2))
    }

    @Test func coordinateMapperClampsPixelsAndMapsCells() {
        let mapper = VTGMouseCoordinateMapper(
            columns: 10,
            rows: 5,
            canvasWidth: 100,
            canvasHeight: 50
        )

        #expect(mapper.cellPosition(pixelX: 0, pixelY: 0)?.gridCol == 0)
        #expect(mapper.cellPosition(pixelX: 0, pixelY: 0)?.gridRow == 0)

        let middle = mapper.cellPosition(pixelX: 55, pixelY: 29)
        #expect(middle?.gridCol == 5)
        #expect(middle?.gridRow == 2)
        #expect(middle?.pixelX == 55)
        #expect(middle?.pixelY == 29)

        let clamped = mapper.snapshot(pixelX: 999, pixelY: -20, modifiers: "shift")
        #expect(clamped?.x == 100)
        #expect(clamped?.y == 0)
        #expect(clamped?.cellX == 10)
        #expect(clamped?.cellY == 1)
        #expect(clamped?.modifiers == "shift")
    }

    @Test func mouseModifiersEncodeWireValue() {
        #expect(VTGMouseModifiers().wireValue == "none")
        #expect(VTGMouseModifiers([.shift, .control, .alt, .command]).wireValue == "shift|ctrl|alt|cmd")

        let snapshot = VTGMouseSnapshot(
            x: 1,
            y: 2,
            cellX: 3,
            cellY: 4,
            modifiers: [.control, .command]
        )
        #expect(snapshot.modifiers == "ctrl|cmd")
    }

    #if os(macOS)
    @Test func appKitMouseModifiersConvertToVTGModifiers() {
        let flags: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        #expect(flags.vtgMouseModifiers == [.shift, .control, .alt, .command])
        #expect(flags.vtgMouseModifiers.wireValue == "shift|ctrl|alt|cmd")
    }
    #endif

    @Test func ansiMouseModeScannerFindsSequencesInStreamOrder() {
        let bytes = Array("prefix\u{1B}[?1000h middle\u{1B}[?1006h\u{1B}[?1016h later\u{1B}[?1000l\u{1B}[?1016l".utf8)

        #expect(VTGANSIMouseModeScanner.scan(bytes) == [
            .vt200(enabled: true),
            .sgr(enabled: true),
            .pixel(enabled: true),
            .vt200(enabled: false),
            .pixel(enabled: false)
        ])
    }
}
