import Foundation
import Testing

@testable import SwiftTerm

final class VectorTerminalGraphicsParserCommandTests {
    private let esc = "\u{1b}"

    private struct ParserFixture {
        var rawCommand: String
        var expectedName: String
        var expectedParameters: [String: String]
        var expectedPayload: String?

        init(
            _ rawCommand: String,
            name expectedName: String,
            parameters expectedParameters: [String: String] = [:],
            payload expectedPayload: String? = nil
        ) {
            self.rawCommand = rawCommand
            self.expectedName = expectedName
            self.expectedParameters = expectedParameters
            self.expectedPayload = expectedPayload
        }
    }

    @Test func parserAcceptsCurrentAndPlannedCommandShapes() {
        let fixtures: [ParserFixture] = [
            ParserFixture("begin", name: "begin"),
            ParserFixture("present", name: "present"),
            ParserFixture("clear", name: "clear"),
            ParserFixture("delete,id=shape1", name: "delete", parameters: ["id": "shape1"]),
            ParserFixture("capabilities?", name: "capabilities?"),
            ParserFixture("canvas?", name: "canvas?"),
            ParserFixture("size?", name: "size?"),
            ParserFixture("resizeEvents,enabled=true", name: "resizeEvents", parameters: ["enabled": "true"]),
            ParserFixture("mouseEvents,enabled=true,mode=raw-click", name: "mouseEvents", parameters: ["enabled": "true", "mode": "raw-click"]),
            ParserFixture("defaultLayer,layer=2", name: "defaultLayer", parameters: ["layer": "2"]),
            ParserFixture("layer,id=shape1,layer=3", name: "layer", parameters: ["id": "shape1", "layer": "3"]),
            ParserFixture("layerScroll,layer=4,x=12,y=-3", name: "layerScroll", parameters: ["layer": "4", "x": "12", "y": "-3"]),
            ParserFixture("layerAlpha,layer=2,alpha=0.45", name: "layerAlpha", parameters: ["layer": "2", "alpha": "0.45"]),
            ParserFixture("clip,layer=4,x=10,y=20,w=300,h=120", name: "clip", parameters: ["layer": "4", "x": "10", "y": "20", "w": "300", "h": "120"]),
            ParserFixture("clipClear,layer=4", name: "clipClear", parameters: ["layer": "4"]),
            ParserFixture("hit,id=button,x=10,y=20,w=100,h=40,target=quit,layer=2", name: "hit", parameters: ["id": "button", "x": "10", "y": "20", "w": "100", "h": "40", "target": "quit", "layer": "2"]),
            ParserFixture("hitClear,id=button", name: "hitClear", parameters: ["id": "button"]),
            ParserFixture("hitClear,layer=2", name: "hitClear", parameters: ["layer": "2"]),
            ParserFixture("hitClear", name: "hitClear"),
            ParserFixture("pixel,id=p1,x=4,y=5,color=#22c55e,layer=1", name: "pixel", parameters: ["id": "p1", "x": "4", "y": "5", "color": "#22c55e", "layer": "1"]),
            ParserFixture("line,id=l1,x1=1,y1=2,x2=3,y2=4,stroke=#5eead4,width=2,layer=1", name: "line", parameters: ["id": "l1", "x1": "1", "y1": "2", "x2": "3", "y2": "4", "stroke": "#5eead4", "width": "2", "layer": "1"]),
            ParserFixture("draw,id=poly,stroke=#22c55e,width=4,layer=1", name: "draw", parameters: ["id": "poly", "stroke": "#22c55e", "width": "4", "layer": "1"], payload: "10,10 20,30 40,10"),
            ParserFixture("curve,id=q,kind=quadratic,x1=1,y1=2,cx=3,cy=4,x2=5,y2=6,stroke=#5eead4,width=3", name: "curve", parameters: ["id": "q", "kind": "quadratic", "x1": "1", "y1": "2", "cx": "3", "cy": "4", "x2": "5", "y2": "6", "stroke": "#5eead4", "width": "3"]),
            ParserFixture("curve,id=c,kind=cubic,x1=1,y1=2,c1x=3,c1y=4,c2x=5,c2y=6,x2=7,y2=8,stroke=#fb7185,width=3", name: "curve", parameters: ["id": "c", "kind": "cubic", "x1": "1", "y1": "2", "c1x": "3", "c1y": "4", "c2x": "5", "c2y": "6", "x2": "7", "y2": "8", "stroke": "#fb7185", "width": "3"]),
            ParserFixture("triangle,id=t,x1=1,y1=2,x2=3,y2=4,x3=5,y3=6,stroke=#22c55e,fill=#07111dcc,width=2", name: "triangle", parameters: ["id": "t", "x1": "1", "y1": "2", "x2": "3", "y2": "4", "x3": "5", "y3": "6", "stroke": "#22c55e", "fill": "#07111dcc", "width": "2"]),
            ParserFixture("path,id=path,stroke=#38bdf8,fill=#38bdf833,width=3", name: "path", parameters: ["id": "path", "stroke": "#38bdf8", "fill": "#38bdf833", "width": "3"], payload: "M 10 10 L 20 20 Q 30 30 40 10 Z"),
            ParserFixture("rect,id=r,x=10,y=20,w=30,h=40,stroke=#22c55e,fill=#07111dcc,width=1,layer=1", name: "rect", parameters: ["id": "r", "x": "10", "y": "20", "w": "30", "h": "40", "stroke": "#22c55e", "fill": "#07111dcc", "width": "1", "layer": "1"]),
            ParserFixture("circle,id=o,cx=10,cy=20,r=30,stroke=#5eead4,fill=#07111d,width=2", name: "circle", parameters: ["id": "o", "cx": "10", "cy": "20", "r": "30", "stroke": "#5eead4", "fill": "#07111d", "width": "2"]),
            ParserFixture("ellipse,id=e,cx=10,cy=20,rx=30,ry=15,stroke=#5eead4,fill=#07111d,width=2", name: "ellipse", parameters: ["id": "e", "cx": "10", "cy": "20", "rx": "30", "ry": "15", "stroke": "#5eead4", "fill": "#07111d", "width": "2"]),
            ParserFixture("text,id=label,x=10,y=20,height=24,value=HELLO,color=#ffffff,layer=1", name: "text", parameters: ["id": "label", "x": "10", "y": "20", "height": "24", "value": "HELLO", "color": "#ffffff", "layer": "1"]),
            ParserFixture("image,id=dog,format=png,x=10,y=20,width=100,height=80", name: "image", parameters: ["id": "dog", "format": "png", "x": "10", "y": "20", "width": "100", "height": "80"], payload: "base64-payload"),
            ParserFixture("spriteUpload,id=enemy,format=png,width=32,height=24", name: "spriteUpload", parameters: ["id": "enemy", "format": "png", "width": "32", "height": "24"], payload: "base64-payload"),
            ParserFixture("vectorSpriteUpload,id=ship,width=64,height=64", name: "vectorSpriteUpload", parameters: ["id": "ship", "width": "64", "height": "64"], payload: "M 0 0 L 64 32 L 0 64 Z"),
            ParserFixture("sprite,id=enemy1,image=enemy,x=10,y=20,rotation=45,scale=1.25,anchorX=0.5,anchorY=0.75,layer=2", name: "sprite", parameters: ["id": "enemy1", "image": "enemy", "x": "10", "y": "20", "rotation": "45", "scale": "1.25", "anchorX": "0.5", "anchorY": "0.75", "layer": "2"]),
            ParserFixture("spriteMove,id=enemy1,x=20,y=30", name: "spriteMove", parameters: ["id": "enemy1", "x": "20", "y": "30"]),
            ParserFixture("spriteRotate,id=enemy1,rotation=90", name: "spriteRotate", parameters: ["id": "enemy1", "rotation": "90"]),
            ParserFixture("spriteAnchor,id=enemy1,anchorX=0.5,anchorY=1", name: "spriteAnchor", parameters: ["id": "enemy1", "anchorX": "0.5", "anchorY": "1"]),
            ParserFixture("spriteTransform,id=enemy1,x=20,y=30,rotation=90,scale=0.75,anchorX=0.5,anchorY=1", name: "spriteTransform", parameters: ["id": "enemy1", "x": "20", "y": "30", "rotation": "90", "scale": "0.75", "anchorX": "0.5", "anchorY": "1"]),
            ParserFixture("spriteRemove,id=enemy", name: "spriteRemove", parameters: ["id": "enemy"]),
            ParserFixture("spriteClear", name: "spriteClear"),
            ParserFixture("startFrame", name: "startFrame"),
            ParserFixture("endFrame", name: "endFrame"),
            ParserFixture("cancelFrame", name: "cancelFrame"),
            ParserFixture("viewportMode,width=320,height=200,scale=fit,layer=1", name: "viewportMode", parameters: ["width": "320", "height": "200", "scale": "fit", "layer": "1"]),
            ParserFixture("viewportScale,layer=1,scale=2,x=10,y=20", name: "viewportScale", parameters: ["layer": "1", "scale": "2", "x": "10", "y": "20"])
        ]

        for fixture in fixtures {
            let command = parseSingleRawCommand(
                fixture.rawCommand,
                payload: fixture.expectedPayload
            )

            #expect(command?.name == fixture.expectedName)
            #expect(command?.parameters == fixture.expectedParameters)
            #expect(command?.payload == fixture.expectedPayload)
        }
    }

    private func parseSingleRawCommand(
        _ rawCommand: String,
        payload: String?
    ) -> VectorTerminalGraphicsCommand? {
        let parser = VectorTerminalGraphicsParser()
        let payloadSuffix = payload.map { ";\($0)" } ?? ""
        let result = parser.feed(bytes("\(esc)_VTG;\(rawCommand)\(payloadSuffix)\(esc)\\")[...])
        return result.commands.first
    }

    private func bytes(_ value: String) -> [UInt8] {
        Array(value.utf8)
    }
}
