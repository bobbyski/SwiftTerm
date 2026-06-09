import Foundation
import Testing

@testable import SwiftTerm

final class VectorTerminalGraphicsParserSpriteCommandTests {
    @Test func parserAcceptsSpriteCommandShapes() {
        let fixtures: [VTGParserFixture] = [
            VTGParserFixture("image,id=dog,format=png,x=10,y=20,width=100,height=80,filter=nearest", name: "image", parameters: ["id": "dog", "format": "png", "x": "10", "y": "20", "width": "100", "height": "80", "filter": "nearest"], payload: "base64-payload"),
            VTGParserFixture("spriteUpload,id=enemy,format=png,width=32,height=24,filter=nearest", name: "spriteUpload", parameters: ["id": "enemy", "format": "png", "width": "32", "height": "24", "filter": "nearest"], payload: "base64-payload"),
            VTGParserFixture("vectorSpriteUpload,id=ship,width=64,height=64", name: "vectorSpriteUpload", parameters: ["id": "ship", "width": "64", "height": "64"], payload: "M 0 0 L 64 32 L 0 64 Z"),
            VTGParserFixture("spriteDataUpload,id=basicship,width=4,height=2,palette=#000000|#5eead4|#fb7185,transparent=0", name: "spriteDataUpload", parameters: ["id": "basicship", "width": "4", "height": "2", "palette": "#000000|#5eead4|#fb7185", "transparent": "0"], payload: "0,1,2,0,1,2,1,0"),
            VTGParserFixture("sprite,id=enemy1,image=enemy,x=10,y=20,rotation=45,scale=1.25,anchorX=0.5,anchorY=0.75,layer=2", name: "sprite", parameters: ["id": "enemy1", "image": "enemy", "x": "10", "y": "20", "rotation": "45", "scale": "1.25", "anchorX": "0.5", "anchorY": "0.75", "layer": "2"]),
            VTGParserFixture("spriteMove,id=enemy1,x=20,y=30", name: "spriteMove", parameters: ["id": "enemy1", "x": "20", "y": "30"]),
            VTGParserFixture("spriteRotate,id=enemy1,rotation=90", name: "spriteRotate", parameters: ["id": "enemy1", "rotation": "90"]),
            VTGParserFixture("spriteAnchor,id=enemy1,anchorX=0.5,anchorY=1", name: "spriteAnchor", parameters: ["id": "enemy1", "anchorX": "0.5", "anchorY": "1"]),
            VTGParserFixture("spriteTransform,id=enemy1,x=20,y=30,rotation=90,scale=0.75,anchorX=0.5,anchorY=1", name: "spriteTransform", parameters: ["id": "enemy1", "x": "20", "y": "30", "rotation": "90", "scale": "0.75", "anchorX": "0.5", "anchorY": "1"]),
            VTGParserFixture("spriteRemove,id=enemy", name: "spriteRemove", parameters: ["id": "enemy"]),
            VTGParserFixture("spriteClear", name: "spriteClear")
        ]

        assertParserFixtures(fixtures)
    }
}
