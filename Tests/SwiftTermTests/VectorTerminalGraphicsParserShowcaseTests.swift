import Foundation
import Testing

@testable import SwiftTerm

final class VectorTerminalGraphicsParserShowcaseTests {
    private let esc = "\u{1b}"

    @Test func parserAcceptsShowcaseReferencePanelEscapes() {
        let references: [(escape: String, name: String)] = [
            (#"ESC _ VTG;draw,id=title-main-0-0,stroke=#5eead4,width=3;x,y x,y ... ESC \"#, "draw"),
            (#"ESC _ VTG;rect,id=shell-frame,x=20,y=20,w=<w>,h=<h>,stroke=#22c55e,fill=#07111dcc,width=1 ESC \"#, "rect"),
            (#"ESC _ VTG;rect,id=shape-rect,x=<x>,y=<y>,w=108,h=92,stroke=#22c55e,fill=#22c55e33,width=3 ESC \"#, "rect"),
            (#"ESC _ VTG;rect,id=shape-rounded-rect,x=<x>,y=<y>,w=108,h=72,stroke=#22c55e,fill=#22c55e33,width=3,radius=24 ESC \"#, "rect"),
            (#"ESC _ VTG;circle,id=shape-circle,cx=<x>,cy=<y>,r=48,stroke=#5eead4,fill=#5eead433,width=4 ESC \"#, "circle"),
            (#"ESC _ VTG;triangle,id=shape-triangle,x1=<n>,y1=<n>,x2=<n>,y2=<n>,x3=<n>,y3=<n>,stroke=#f8fafc,fill=#3b82f655,width=3 ESC \"#, "triangle"),
            (#"ESC _ VTG;triangle,id=shape-rounded-triangle,x1=<n>,y1=<n>,x2=<n>,y2=<n>,x3=<n>,y3=<n>,stroke=#f8fafc,fill=#3b82f655,width=3,radius=24 ESC \"#, "triangle"),
            (#"ESC _ VTG;draw,id=drawing-polyline,stroke=#22c55e,width=4;x,y x,y x,y ... ESC \"#, "draw"),
            (#"ESC _ VTG;curve,id=drawing-quad,kind=quadratic,x1=<n>,y1=<n>,cx=<n>,cy=<n>,x2=<n>,y2=<n>,stroke=#5eead4,width=5 ESC \"#, "curve"),
            (#"ESC _ VTG;curve,id=drawing-cubic,kind=cubic,x1=<n>,y1=<n>,c1x=<n>,c1y=<n>,c2x=<n>,c2y=<n>,x2=<n>,y2=<n>,stroke=#fb7185,width=5 ESC \"#, "curve"),
            (#"ESC _ VTG;path,id=drawing-path,stroke=#3b82f6,fill=#3b82f633,width=3;M ... L ... Q ... Z ESC \"#, "path"),
            (#"ESC _ VTG;spriteUpload,id=galagaenemy,format=png,width=48,height=32,filter=nearest;<base64> ESC \"#, "spriteUpload"),
            (#"ESC _ VTG;sprite,id=spriteenemy00,image=galagaenemy,x=<x>,y=<y>,rotation=0,scale=1 ESC \"#, "sprite"),
            (#"ESC _ VTG;vectorSpriteUpload,id=vectorship,width=42,height=34,stroke=#22c55e,fill=#22c55e33,lineWidth=2;M ... Z ESC \"#, "vectorSpriteUpload"),
            (#"ESC _ VTG;spriteTransform,id=spriteenemy00,x=<x>,y=<y>,rotation=<r>,scale=1.15 ESC \"#, "spriteTransform"),
            (#"ESC _ VTG;spriteAnchor,id=spriteplayer,anchorX=0.5,anchorY=0.75 ESC \"#, "spriteAnchor"),
            (#"ESC _ VTG;layerScroll,layer=2,x=<dx>,y=0 ESC \"#, "layerScroll"),
            (#"ESC _ VTG;clip,layer=2,x=<x>,y=<y>,w=<w>,h=<h> ESC \"#, "clip"),
            (#"ESC _ VTG;image,id=raster-sample,format=jpeg,x=<x>,y=<y>,width=<w>,height=<h>;<base64> ESC \"#, "image"),
            (#"ESC _ VTG;delete,id=raster-sample ESC \"#, "delete"),
            (#"ESC _ VTG;line,id=ttt-v1,x1=<n>,y1=<n>,x2=<n>,y2=<n>,stroke=#3b82f6,width=5 ESC \"#, "line"),
            (#"ESC _ VTG;circle,id=ttt-o,cx=<n>,cy=<n>,r=<n>,stroke=#5eead4,width=8 ESC \"#, "circle"),
            (#"ESC _ VTG;mouse,type=click,button=0,x=<px>,y=<px>,cellX=<col>,cellY=<row>,mods=none ESC \"#, "mouse"),
            (#"ESC _ VTG;rect,id=layer-card-2,...,layer=2 ESC \"#, "rect"),
            (#"ESC _ VTG;layer,id=layer-moved-card,value=4 ESC \"#, "layer"),
            (#"ESC _ VTG;layerAlpha,layer=3,alpha=0.55 ESC \"#, "layerAlpha"),
            (#"ESC _ VTG;clip,layer=4,x=<x>,y=<y>,w=<w>,h=<h> ESC \"#, "clip"),
            (#"ESC _ VTG;layerScroll,layer=4,x=<offset>,y=0 ESC \"#, "layerScroll"),
            (#"ESC _ VTG;hit,id=layersHit,x=<x>,y=<y>,w=<w>,h=<h>,target=layersHitButton ESC \"#, "hit"),
            (#"ESC _ VTG;startFrame,id=showcaseFrame,timeout=500 ESC \"#, "startFrame"),
            (#"ESC _ VTG;endFrame,id=showcaseFrame ESC \"#, "endFrame"),
            (#"ESC _ VTG;cancelFrame,id=showcaseFrame ESC \"#, "cancelFrame")
        ]

        for reference in references {
            let command = parseDisplayEscape(reference.escape)

            #expect(command?.name == reference.name)
        }
    }

    private func parseDisplayEscape(_ displayEscape: String) -> VectorTerminalGraphicsCommand? {
        let raw = displayEscape
            .replacingOccurrences(of: "ESC _ ", with: "\(esc)_")
            .replacingOccurrences(of: " ESC \\", with: "\(esc)\\")
        let parser = VectorTerminalGraphicsParser()
        let result = parser.feed(bytes(raw)[...])
        return result.commands.first
    }

    private func bytes(_ value: String) -> [UInt8] {
        Array(value.utf8)
    }
}
