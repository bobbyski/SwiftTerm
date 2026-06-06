import Foundation
import Testing

@testable import SwiftTerm

final class VectorTerminalGraphicsParserFrameCommandTests {
    @Test func parserAcceptsFrameAndViewportCommandShapes() {
        let fixtures: [VTGParserFixture] = [
            VTGParserFixture("startFrame", name: "startFrame"),
            VTGParserFixture("endFrame", name: "endFrame"),
            VTGParserFixture("cancelFrame", name: "cancelFrame"),
            VTGParserFixture("viewportMode,width=320,height=200,scale=fit,layer=1", name: "viewportMode", parameters: ["width": "320", "height": "200", "scale": "fit", "layer": "1"]),
            VTGParserFixture("viewportScale,layer=1,scale=2,x=10,y=20", name: "viewportScale", parameters: ["layer": "1", "scale": "2", "x": "10", "y": "20"])
        ]

        assertParserFixtures(fixtures)
    }
}
