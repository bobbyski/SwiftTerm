import Foundation
import Testing

@testable import SwiftTerm

/// Raster mode: drawing painted into the text plane, and never retained under
/// an id the guest could reuse, delete or move.
final class VTGRasterModeTests {
    private let canvas = VTGCanvasSize(width: 640, height: 480)

    @Test func drawingLandsOnTheTextPlaneUnderHostIDs() {
        let controller = VTGHostController()
        controller.process([command("rasterMode", ["enabled": "1"])], canvas: canvas)
        controller.process([
            command("line", ["id": "beam", "x1": "0", "y1": "0", "x2": "10", "y2": "10"]),
            command("line", ["id": "beam", "x1": "0", "y1": "20", "x2": "10", "y2": "30"]),
        ], canvas: canvas)

        // Twice, not once: the same id paints again rather than replacing, as a
        // framebuffer does.
        #expect(controller.scene.primitives.count == 2)
        #expect(controller.scene.layersByID.values.allSatisfy { $0 == VTGLayerModel.textPlaneLayer })
        #expect(controller.scene.layersByID.keys.contains("beam") == false)
    }

    @Test func theGuestCannotDeleteOrMoveWhatItDrew() {
        let controller = VTGHostController()
        controller.process([
            command("rasterMode", ["enabled": "1"]),
            command("rect", ["id": "box", "x": "0", "y": "0", "width": "8", "height": "8"]),
            command("delete", ["id": "box"]),
            command("layer", ["id": "box", "layer": "2"]),
        ], canvas: canvas)

        #expect(controller.scene.primitives.count == 1)
        #expect(controller.scene.layersByID.values.allSatisfy { $0 == VTGLayerModel.textPlaneLayer })
    }

    @Test func switchingEitherWayClearsTheScene() {
        let controller = VTGHostController()
        controller.process([command("rect", ["id": "box", "x": "0", "y": "0", "width": "8", "height": "8"])], canvas: canvas)
        #expect(controller.scene.primitives.count == 1)

        controller.process([command("rasterMode", ["enabled": "1"])], canvas: canvas)
        #expect(controller.isRasterMode)
        #expect(controller.scene.primitives.isEmpty)

        controller.process([command("pixel", ["id": "dot", "x": "1", "y": "1"])], canvas: canvas)
        controller.process([command("rasterMode", ["enabled": "0"])], canvas: canvas)
        #expect(!controller.isRasterMode)
        #expect(controller.scene.primitives.isEmpty)
    }

    /// Off, the retained scene behaves exactly as before.
    @Test func retainedBehaviourIsUntouchedWithTheModeOff() {
        let controller = VTGHostController()
        controller.process([
            command("line", ["id": "beam", "x1": "0", "y1": "0", "x2": "10", "y2": "10"]),
            command("line", ["id": "beam", "x1": "0", "y1": "20", "x2": "10", "y2": "30"]),
        ], canvas: canvas)

        #expect(controller.scene.primitives.count == 1)
        controller.process([command("delete", ["id": "beam"])], canvas: canvas)
        #expect(controller.scene.primitives.isEmpty)
    }

    @Test func aNewSessionStartsWithTheRetainedScene() {
        let controller = VTGHostController()
        controller.process([command("rasterMode", ["enabled": "1"])], canvas: canvas)
        controller.resetSession()
        #expect(!controller.isRasterMode)
    }

    private func command(
        _ name: String,
        _ parameters: [String: String] = [:]
    ) -> VectorTerminalGraphicsCommand {
        VectorTerminalGraphicsCommand(name: name, parameters: parameters, payload: nil)
    }
}
