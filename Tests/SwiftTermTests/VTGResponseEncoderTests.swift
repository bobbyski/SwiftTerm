import Foundation
import Testing

@testable import SwiftTerm

final class VTGResponseEncoderTests {
    private let esc = "\u{1B}"

    @Test func encodesCapabilitiesResponse() {
        let response = VTGResponseEncoder.capabilities(canvas: VTGCanvasSize(width: 800, height: 600))

        #expect(response.hasPrefix("\u{1B}_VTG;capabilities,"))
        #expect(response.contains("protocol=VTG"))
        #expect(response.contains("schema=vtg.capabilities.v1"))
        #expect(response.contains("version=1.5.4"))
        #expect(response.contains("canvasWidth=800"))
        #expect(response.contains("canvasHeight=600"))
        #expect(response.contains("commands=begin|present|clear|delete|capabilities?|canvas?|size?|graphicsVisible|graphicsVisible?|glyphSize?|resizeEvents|mouseEvents|defaultLayer|layer|layerScroll|layerAlpha|viewportMode|viewportScale|clip|clipClear|hit|hitClear|pixel|clearRect|line|draw|curve|triangle|path|rect|circle|ellipse|text|image|startFrame|endFrame|cancelFrame|spriteUpload|vectorSpriteUpload|spriteDataUpload|sprite|spriteMove|spriteRotate|spriteAnchor|spriteTransform|spriteRemove|spriteClear"))
        #expect(response.contains("planned="))
        #expect(response.contains("primitives=pixel|clearRect|line|draw|curve|triangle|path|rect|circle|ellipse|text|image|sprite"))
        #expect(response.contains("underText=pixel|line|draw|curve|triangle|path|rect|circle|ellipse"))
        #expect(response.contains("raster=image|filter"))
        #expect(response.contains("sprites=bitmap|vector|indexed|move|rotate|scale|filter"))
        #expect(response.contains("layers=-1-4"))
        #expect(response.contains("textPlane=reserved"))
        #expect(response.contains("layerAlpha=1-4"))
        #expect(response.contains("events=mouse|resize|frame"))
        #expect(response.hasSuffix("\u{1B}\\"))
    }

    @Test func encodesHostRendererInCapabilitiesResponse() {
        let response = VTGResponseEncoder.capabilities(
            canvas: VTGCanvasSize(width: 800, height: 600),
            renderer: "metal"
        )

        #expect(response.contains("renderer=metal"))
    }

    @Test func encodesCanvasAndResizeResponses() {
        let canvas = VTGCanvasSize(width: 120, height: 80)

        #expect(VTGResponseEncoder.canvasResponse(commandName: "canvas", canvas: canvas) == "\u{1B}_VTG;canvas,width=120,height=80\u{1B}\\")
        #expect(VTGResponseEncoder.canvasResponse(commandName: "size", canvas: canvas) == "\u{1B}_VTG;size,width=120,height=80\u{1B}\\")
        #expect(VTGResponseEncoder.resize(canvas: canvas) == "\u{1B}_VTG;resize,width=120,height=80\u{1B}\\")
    }

    @Test func encodesGlyphSizeResponse() {
        #expect(VTGResponseEncoder.glyphSize(width: 9, height: 18) == "\u{1B}_VTG;glyphSize,character=W,width=9,height=18\u{1B}\\")
        #expect(VTGResponseEncoder.glyphSize(width: 8.625, height: 18.25) == "\u{1B}_VTG;glyphSize,character=W,width=8.625,height=18.25\u{1B}\\")
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
            targetID: "button",
            viewportLayer: 4,
            virtualX: 120,
            virtualY: 80
        )

        #expect(VTGResponseEncoder.mouse(event) == "\u{1B}_VTG;mouse,type=scroll,button=5,x=10,y=20,cellX=2,cellY=3,scrollX=0,scrollY=-4,viewportLayer=4,virtualX=120,virtualY=80,mods=shift|cmd,hit=quit,target=button\u{1B}\\")
    }

    @Test func encodesFrameLifecycleResponses() {
        #expect(VTGResponseEncoder.frameEvent("frameStarted", id: "f1", timeoutMilliseconds: 500) == "\u{1B}_VTG;frameStarted,id=f1,timeout=500\u{1B}\\")
        #expect(VTGResponseEncoder.frameEvent("frameCommitted", id: "f1") == "\u{1B}_VTG;frameCommitted,id=f1\u{1B}\\")
        #expect(VTGResponseEncoder.frameEvent("frameCanceled", id: "f1", reason: "app") == "\u{1B}_VTG;frameCanceled,id=f1,reason=app\u{1B}\\")
        #expect(VTGResponseEncoder.frameEvent("frameTimeout", id: "f1", reason: "timeout") == "\u{1B}_VTG;frameTimeout,id=f1,reason=timeout\u{1B}\\")
        #expect(VTGResponseEncoder.frameEvent("frameRejected", id: "f2", reason: "nested") == "\u{1B}_VTG;frameRejected,id=f2,reason=nested\u{1B}\\")
    }

}
