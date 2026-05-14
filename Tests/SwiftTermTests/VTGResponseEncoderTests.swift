import Foundation
import Testing

@testable import SwiftTerm

final class VTGResponseEncoderTests {
    @Test func encodesCapabilitiesResponse() {
        let response = VTGResponseEncoder.capabilities(canvas: VTGCanvasSize(width: 800, height: 600))

        #expect(response.hasPrefix("\u{1B}_VTG;capabilities,"))
        #expect(response.contains("protocol=VTG"))
        #expect(response.contains("schema=vtg.capabilities.v1"))
        #expect(response.contains("version=0.1"))
        #expect(response.contains("canvasWidth=800"))
        #expect(response.contains("canvasHeight=600"))
        #expect(response.contains("commands=begin|present|clear|delete|capabilities?|canvas?|size?|resizeEvents|mouseEvents|defaultLayer|layer|layerScroll|layerAlpha|clip|clipClear|hit|hitClear|pixel|line|draw|curve|triangle|path|rect|circle|ellipse|text|image|spriteUpload|vectorSpriteUpload|sprite|spriteMove|spriteRotate|spriteAnchor|spriteTransform|spriteRemove|spriteClear"))
        #expect(response.contains("planned=startFrame|endFrame|cancelFrame|viewportMode|viewportClear"))
        #expect(response.contains("primitives=pixel|line|draw|curve|triangle|path|rect|circle|ellipse|text|image|sprite"))
        #expect(response.contains("sprites=bitmap|vector|move|rotate|scale"))
        #expect(response.contains("layers=0-4"))
        #expect(response.contains("layerAlpha=1-4"))
        #expect(response.contains("events=mouse|resize"))
        #expect(response.hasSuffix("\u{1B}\\"))
    }

    @Test func encodesCanvasAndResizeResponses() {
        let canvas = VTGCanvasSize(width: 120, height: 80)

        #expect(VTGResponseEncoder.canvasResponse(commandName: "canvas", canvas: canvas) == "\u{1B}_VTG;canvas,width=120,height=80\u{1B}\\")
        #expect(VTGResponseEncoder.canvasResponse(commandName: "size", canvas: canvas) == "\u{1B}_VTG;size,width=120,height=80\u{1B}\\")
        #expect(VTGResponseEncoder.resize(canvas: canvas) == "\u{1B}_VTG;resize,width=120,height=80\u{1B}\\")
    }

    @Test func encodesMouseResponseWithOptionalFields() {
        let event = VTGMouseEventPayload(
            type: "scroll",
            button: 5,
            x: 10,
            y: 20,
            cellX: 2,
            cellY: 3,
            modifiers: "shift|cmd",
            scrollX: 0,
            scrollY: -4,
            hitID: "quit",
            targetID: "button"
        )

        #expect(VTGResponseEncoder.mouse(event) == "\u{1B}_VTG;mouse,type=scroll,button=5,x=10,y=20,cellX=2,cellY=3,scrollX=0,scrollY=-4,mods=shift|cmd,hit=quit,target=button\u{1B}\\")
    }
}
