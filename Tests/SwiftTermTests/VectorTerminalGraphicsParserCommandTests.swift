import Foundation
import Testing

@testable import SwiftTerm

final class VectorTerminalGraphicsParserCommandTests {
    @Test func parserAcceptsCurrentAndPlannedCommandShapes() {
        let fixtures: [VTGParserFixture] = [
            VTGParserFixture("begin", name: "begin"),
            VTGParserFixture("present", name: "present"),
            VTGParserFixture("clear", name: "clear"),
            VTGParserFixture("delete,id=shape1", name: "delete", parameters: ["id": "shape1"]),
            VTGParserFixture("capabilities?", name: "capabilities?"),
            VTGParserFixture("canvas?", name: "canvas?"),
            VTGParserFixture("size?", name: "size?"),
            VTGParserFixture("resizeEvents,enabled=true", name: "resizeEvents", parameters: ["enabled": "true"]),
            VTGParserFixture("mouseEvents,enabled=true,mode=raw-click", name: "mouseEvents", parameters: ["enabled": "true", "mode": "raw-click"]),
            VTGParserFixture("defaultLayer,layer=2", name: "defaultLayer", parameters: ["layer": "2"]),
            VTGParserFixture("layer,id=shape1,layer=3", name: "layer", parameters: ["id": "shape1", "layer": "3"]),
            VTGParserFixture("layerScroll,layer=4,x=12,y=-3", name: "layerScroll", parameters: ["layer": "4", "x": "12", "y": "-3"]),
            VTGParserFixture("layerAlpha,layer=2,alpha=0.45", name: "layerAlpha", parameters: ["layer": "2", "alpha": "0.45"]),
            VTGParserFixture("clip,layer=4,x=10,y=20,w=300,h=120", name: "clip", parameters: ["layer": "4", "x": "10", "y": "20", "w": "300", "h": "120"]),
            VTGParserFixture("clipClear,layer=4", name: "clipClear", parameters: ["layer": "4"]),
            VTGParserFixture("hit,id=button,x=10,y=20,w=100,h=40,target=quit,layer=2", name: "hit", parameters: ["id": "button", "x": "10", "y": "20", "w": "100", "h": "40", "target": "quit", "layer": "2"]),
            VTGParserFixture("hitClear,id=button", name: "hitClear", parameters: ["id": "button"]),
            VTGParserFixture("hitClear,layer=2", name: "hitClear", parameters: ["layer": "2"]),
            VTGParserFixture("hitClear", name: "hitClear"),
            VTGParserFixture("pixel,id=p1,x=4,y=5,color=#22c55e,layer=1", name: "pixel", parameters: ["id": "p1", "x": "4", "y": "5", "color": "#22c55e", "layer": "1"]),
            VTGParserFixture("line,id=l1,x1=1,y1=2,x2=3,y2=4,stroke=#5eead4,width=2,layer=1", name: "line", parameters: ["id": "l1", "x1": "1", "y1": "2", "x2": "3", "y2": "4", "stroke": "#5eead4", "width": "2", "layer": "1"]),
            VTGParserFixture("draw,id=poly,stroke=#22c55e,width=4,layer=1", name: "draw", parameters: ["id": "poly", "stroke": "#22c55e", "width": "4", "layer": "1"], payload: "10,10 20,30 40,10"),
            VTGParserFixture("curve,id=q,kind=quadratic,x1=1,y1=2,cx=3,cy=4,x2=5,y2=6,stroke=#5eead4,width=3", name: "curve", parameters: ["id": "q", "kind": "quadratic", "x1": "1", "y1": "2", "cx": "3", "cy": "4", "x2": "5", "y2": "6", "stroke": "#5eead4", "width": "3"]),
            VTGParserFixture("curve,id=c,kind=cubic,x1=1,y1=2,c1x=3,c1y=4,c2x=5,c2y=6,x2=7,y2=8,stroke=#fb7185,width=3", name: "curve", parameters: ["id": "c", "kind": "cubic", "x1": "1", "y1": "2", "c1x": "3", "c1y": "4", "c2x": "5", "c2y": "6", "x2": "7", "y2": "8", "stroke": "#fb7185", "width": "3"]),
            VTGParserFixture("triangle,id=t,x1=1,y1=2,x2=3,y2=4,x3=5,y3=6,stroke=#22c55e,fill=#07111dcc,width=2", name: "triangle", parameters: ["id": "t", "x1": "1", "y1": "2", "x2": "3", "y2": "4", "x3": "5", "y3": "6", "stroke": "#22c55e", "fill": "#07111dcc", "width": "2"]),
            VTGParserFixture("path,id=path,stroke=#38bdf8,fill=#38bdf833,width=3", name: "path", parameters: ["id": "path", "stroke": "#38bdf8", "fill": "#38bdf833", "width": "3"], payload: "M 10 10 L 20 20 Q 30 30 40 10 Z"),
            VTGParserFixture("rect,id=r,x=10,y=20,w=30,h=40,stroke=#22c55e,fill=#07111dcc,width=1,layer=1", name: "rect", parameters: ["id": "r", "x": "10", "y": "20", "w": "30", "h": "40", "stroke": "#22c55e", "fill": "#07111dcc", "width": "1", "layer": "1"]),
            VTGParserFixture("circle,id=o,cx=10,cy=20,r=30,stroke=#5eead4,fill=#07111d,width=2", name: "circle", parameters: ["id": "o", "cx": "10", "cy": "20", "r": "30", "stroke": "#5eead4", "fill": "#07111d", "width": "2"]),
            VTGParserFixture("ellipse,id=e,cx=10,cy=20,rx=30,ry=15,stroke=#5eead4,fill=#07111d,width=2", name: "ellipse", parameters: ["id": "e", "cx": "10", "cy": "20", "rx": "30", "ry": "15", "stroke": "#5eead4", "fill": "#07111d", "width": "2"]),
            VTGParserFixture("text,id=label,x=10,y=20,height=24,value=HELLO,color=#ffffff,layer=1", name: "text", parameters: ["id": "label", "x": "10", "y": "20", "height": "24", "value": "HELLO", "color": "#ffffff", "layer": "1"])
        ]

        assertParserFixtures(fixtures)
    }
}
