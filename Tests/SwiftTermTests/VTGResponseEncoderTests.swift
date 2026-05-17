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
        #expect(response.contains("version=0.1"))
        #expect(response.contains("canvasWidth=800"))
        #expect(response.contains("canvasHeight=600"))
        #expect(response.contains("commands=begin|present|clear|delete|capabilities?|canvas?|size?|resizeEvents|mouseEvents|defaultLayer|layer|layerScroll|layerAlpha|clip|clipClear|hit|hitClear|pixel|line|draw|curve|triangle|path|rect|circle|ellipse|text|image|startFrame|endFrame|cancelFrame|spriteUpload|vectorSpriteUpload|sprite|spriteMove|spriteRotate|spriteAnchor|spriteTransform|spriteRemove|spriteClear"))
        #expect(response.contains("planned=viewportMode|viewportScale"))
        #expect(response.contains("primitives=pixel|line|draw|curve|triangle|path|rect|circle|ellipse|text|image|sprite"))
        #expect(response.contains("sprites=bitmap|vector|move|rotate|scale"))
        #expect(response.contains("layers=0-4"))
        #expect(response.contains("layerAlpha=1-4"))
        #expect(response.contains("events=mouse|resize|frame"))
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

    @Test func encodesFrameLifecycleResponses() {
        #expect(VTGResponseEncoder.frameEvent("frameStarted", id: "f1", timeoutMilliseconds: 500) == "\u{1B}_VTG;frameStarted,id=f1,timeout=500\u{1B}\\")
        #expect(VTGResponseEncoder.frameEvent("frameCommitted", id: "f1") == "\u{1B}_VTG;frameCommitted,id=f1\u{1B}\\")
        #expect(VTGResponseEncoder.frameEvent("frameCanceled", id: "f1", reason: "app") == "\u{1B}_VTG;frameCanceled,id=f1,reason=app\u{1B}\\")
        #expect(VTGResponseEncoder.frameEvent("frameTimeout", id: "f1", reason: "timeout") == "\u{1B}_VTG;frameTimeout,id=f1,reason=timeout\u{1B}\\")
    }

    @Test func advertisedCommandsHaveParserFixtures() {
        let parser = VectorTerminalGraphicsParser()
        let advertised = VTGResponseEncoder.defaultCommands + VTGResponseEncoder.plannedCommands

        for commandName in advertised {
            let raw = parserFixture(for: commandName)
            let result = parser.feed(Array("\(esc)_VTG;\(raw)\(esc)\\".utf8)[...])

            #expect(result.commands.first?.name == commandName)
        }
    }

    private func parserFixture(for commandName: String) -> String {
        switch commandName {
        case "begin", "present", "clear", "capabilities?", "canvas?", "size?", "hitClear", "spriteClear", "startFrame", "endFrame", "cancelFrame":
            return commandName
        case "delete":
            return "delete,id=shape1"
        case "resizeEvents":
            return "resizeEvents,enabled=true"
        case "mouseEvents":
            return "mouseEvents,enabled=true,mode=raw"
        case "defaultLayer":
            return "defaultLayer,layer=1"
        case "layer":
            return "layer,id=shape1,layer=2"
        case "layerScroll":
            return "layerScroll,layer=2,x=12,y=-3"
        case "layerAlpha":
            return "layerAlpha,layer=2,alpha=0.5"
        case "clip":
            return "clip,layer=2,x=10,y=20,w=100,h=80"
        case "clipClear":
            return "clipClear,layer=2"
        case "hit":
            return "hit,id=button,x=10,y=20,w=100,h=40,target=quit,layer=2"
        case "pixel":
            return "pixel,id=p1,x=4,y=5,color=#22c55e"
        case "line":
            return "line,id=l1,x1=1,y1=2,x2=3,y2=4,stroke=#5eead4,width=2"
        case "draw":
            return "draw,id=poly,stroke=#22c55e,width=4;10,10 20,30 40,10"
        case "curve":
            return "curve,id=q,kind=quadratic,x1=1,y1=2,cx=3,cy=4,x2=5,y2=6,stroke=#5eead4,width=3"
        case "triangle":
            return "triangle,id=t,x1=1,y1=2,x2=3,y2=4,x3=5,y3=6,stroke=#22c55e,fill=#07111dcc,width=2"
        case "path":
            return "path,id=path,stroke=#38bdf8,fill=#38bdf833,width=3;M 10 10 L 20 20 Z"
        case "rect":
            return "rect,id=r,x=10,y=20,w=30,h=40,stroke=#22c55e,fill=#07111dcc,width=1"
        case "circle":
            return "circle,id=o,cx=10,cy=20,r=30,stroke=#5eead4,fill=#07111d,width=2"
        case "ellipse":
            return "ellipse,id=e,cx=10,cy=20,rx=30,ry=15,stroke=#5eead4,fill=#07111d,width=2"
        case "text":
            return "text,id=label,x=10,y=20,height=24,value=HELLO,color=#ffffff"
        case "image":
            return "image,id=dog,format=png,x=10,y=20,width=100,height=80;base64-payload"
        case "spriteUpload":
            return "spriteUpload,id=enemy,format=png,width=32,height=24;base64-payload"
        case "vectorSpriteUpload":
            return "vectorSpriteUpload,id=ship,width=64,height=64;M 0 0 L 64 32 L 0 64 Z"
        case "sprite":
            return "sprite,id=enemy1,image=enemy,x=10,y=20,rotation=45,scale=1.25,anchorX=0.5,anchorY=0.75,layer=2"
        case "spriteMove":
            return "spriteMove,id=enemy1,x=20,y=30"
        case "spriteRotate":
            return "spriteRotate,id=enemy1,rotation=90"
        case "spriteAnchor":
            return "spriteAnchor,id=enemy1,anchorX=0.5,anchorY=1"
        case "spriteTransform":
            return "spriteTransform,id=enemy1,x=20,y=30,rotation=90,scale=0.75,anchorX=0.5,anchorY=1"
        case "spriteRemove":
            return "spriteRemove,id=enemy"
        case "viewportMode":
            return "viewportMode,width=320,height=200,scale=fit,layer=1"
        case "viewportScale":
            return "viewportScale,layer=1,scale=2,x=10,y=20"
        default:
            Issue.record("Missing parser fixture for advertised VTG command: \(commandName)")
            return commandName
        }
    }
}
