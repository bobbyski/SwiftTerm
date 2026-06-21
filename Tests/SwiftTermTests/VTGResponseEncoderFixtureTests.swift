import Foundation
import Testing

@testable import SwiftTerm

final class VTGResponseEncoderFixtureTests {
    private let esc = "\u{1B}"

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
        case "clearRect":
            return "clearRect,id=erase,x=4,y=5,w=20,h=30,layer=2"
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
            return "spriteUpload,id=enemy,format=png,width=32,height=24,filter=nearest;base64-payload"
        case "vectorSpriteUpload":
            return "vectorSpriteUpload,id=ship,width=64,height=64;M 0 0 L 64 32 L 0 64 Z"
        case "spriteDataUpload":
            return "spriteDataUpload,id=basicship,width=4,height=2,palette=#000000|#5eead4|#fb7185,transparent=0,filter=nearest;0,1,2,0,1,2,1,0"
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
