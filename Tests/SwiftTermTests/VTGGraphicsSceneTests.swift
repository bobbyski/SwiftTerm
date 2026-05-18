import Foundation
import Testing

@testable import SwiftTerm

final class VTGGraphicsSceneTests {
    @Test func retainsAndReplacesPrimitiveByID() {
        let scene = VTGGraphicsScene()

        scene.apply(command("line", [
            "id": "axis",
            "x1": "0",
            "y1": "0",
            "x2": "10",
            "y2": "10",
            "stroke": "#22c55e",
            "width": "2"
        ]))
        scene.apply(command("line", [
            "id": "axis",
            "x1": "0",
            "y1": "0",
            "x2": "20",
            "y2": "20",
            "stroke": "#22c55e",
            "width": "4"
        ]))

        #expect(scene.primitives.count == 1)
        guard case .line(_, _, _, let x2, let y2, _, let width) = scene.primitives.first else {
            Issue.record("Expected retained line primitive")
            return
        }
        #expect(x2 == 20)
        #expect(y2 == 20)
        #expect(width == 4)
    }

    @Test func renderPrimitivesAreSortedByLayerThenInsertionOrder() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", ["id": "front", "layer": "3", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("rect", ["id": "back", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("rect", ["id": "middle", "layer": "2", "x": "0", "y": "0", "w": "10", "h": "10"]))

        #expect(scene.renderPrimitives.map(\.id) == ["back", "middle", "front"])
    }

    @Test func rectParsesOptionalCornerRadius() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", [
            "id": "rounded",
            "x": "10",
            "y": "20",
            "w": "30",
            "h": "40",
            "radius": "8"
        ]))

        guard case .rect(_, _, _, _, _, let radius, _, _, _) = scene.primitives.first else {
            Issue.record("Expected retained rect primitive")
            return
        }
        #expect(radius == 8)
    }

    @Test func layerCommandMovesExistingPrimitiveWithoutRedraw() {
        let scene = VTGGraphicsScene()

        scene.apply(command("rect", ["id": "movable", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("layer", ["id": "movable", "layer": "4"]))

        #expect(scene.primitives.count == 1)
        #expect(scene.layer(for: scene.primitives[0]) == VTGLayerModel.lastOverlayLayer)
    }

    @Test func defaultLayerAndObjectLayerAcceptCanonicalLayerParameter() {
        let scene = VTGGraphicsScene()

        scene.apply(command("defaultLayer", ["layer": "2"]))
        scene.apply(command("rect", ["id": "pane", "x": "0", "y": "0", "w": "10", "h": "10"]))
        #expect(scene.layer(for: scene.primitives[0]) == 2)

        scene.apply(command("layer", ["id": "pane", "layer": "3"]))
        #expect(scene.layer(for: scene.primitives[0]) == 3)

        scene.apply(command("rect", ["id": "pane", "x": "0", "y": "0", "w": "20", "h": "20"]))
        #expect(scene.primitives.count == 1)
        #expect(scene.layer(for: scene.primitives[0]) == 3)
    }

    @Test func layerCommandIgnoresUnknownPrimitiveIDs() {
        let scene = VTGGraphicsScene()

        scene.apply(command("layer", ["id": "missing", "value": "4"]))

        #expect(scene.layersByID.isEmpty)
        #expect(scene.primitives.isEmpty)
    }

    @Test func hitRegionsPreferTopmostLayerAndRespectClip() {
        let scene = VTGGraphicsScene()

        scene.apply(command("clip", ["layer": "2", "x": "0", "y": "0", "w": "50", "h": "50"]))
        scene.apply(command("hit", ["id": "back", "layer": "1", "x": "0", "y": "0", "w": "100", "h": "100"]))
        scene.apply(command("hit", ["id": "front", "layer": "2", "x": "0", "y": "0", "w": "100", "h": "100"]))

        #expect(scene.hitRegion(at: VTGPoint(x: 25, y: 25))?.id == "front")
        #expect(scene.hitRegion(at: VTGPoint(x: 75, y: 75))?.id == "back")
    }

    @Test func hitClearRemovesByIDLayerOrAll() {
        let scene = VTGGraphicsScene()

        scene.apply(command("hit", ["id": "one", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("hit", ["id": "two", "layer": "2", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("hit", ["id": "three", "layer": "2", "x": "20", "y": "0", "w": "10", "h": "10"]))

        scene.apply(command("hitClear", ["id": "one"]))
        #expect(scene.hitRegions.keys.sorted() == ["three", "two"])

        scene.apply(command("hitClear", ["layer": "2"]))
        #expect(scene.hitRegions.isEmpty)

        scene.apply(command("hit", ["id": "four", "layer": "1", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("hit", ["id": "five", "layer": "3", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("hitClear"))
        #expect(scene.hitRegions.isEmpty)
    }

    @Test func layerModelClampsDrawingLayersAndReservesTextPlaneFromScrolling() {
        let scene = VTGGraphicsScene()

        scene.apply(command("defaultLayer", ["value": "-2"]))
        #expect(scene.defaultLayer == VTGLayerModel.textPlaneLayer)

        scene.apply(command("rect", ["id": "textPlane", "x": "0", "y": "0", "w": "10", "h": "10"]))
        #expect(scene.layer(for: scene.primitives[0]) == VTGLayerModel.textPlaneLayer)

        scene.apply(command("defaultLayer", ["value": "99"]))
        #expect(scene.defaultLayer == VTGLayerModel.lastOverlayLayer)

        scene.apply(command("layerScroll", ["layer": "0", "x": "10", "y": "20"]))
        #expect(scene.offset(for: VTGLayerModel.textPlaneLayer) == .zero)

        scene.apply(command("layerScroll", ["layer": "4", "x": "10", "y": "20"]))
        #expect(scene.offset(for: VTGLayerModel.lastOverlayLayer) == VTGLayerOffset(x: 10, y: 20))
    }

    @Test func layerAlphaAppliesOnlyToOverlayLayersAndClampsValues() {
        let scene = VTGGraphicsScene()

        scene.apply(command("layerAlpha", ["layer": "0", "alpha": "0.25"]))
        #expect(scene.alpha(for: VTGLayerModel.textPlaneLayer) == 1)

        scene.apply(command("layerAlpha", ["layer": "3", "alpha": "0.45"]))
        #expect(scene.alpha(for: 3) == 0.45)

        scene.apply(command("layerAlpha", ["layer": "3", "alpha": "2"]))
        #expect(scene.alpha(for: 3) == 1)

        scene.apply(command("layerAlpha", ["layer": "3", "alpha": "-1"]))
        #expect(scene.alpha(for: 3) == 0)
    }

    @Test func viewportModeStoresFixedResolutionOverlayStateOnly() {
        let scene = VTGGraphicsScene()

        scene.apply(command("viewportMode", ["layer": "0", "width": "320", "height": "200", "scale": "fit"]))
        #expect(scene.viewportMode(for: 0) == nil)

        scene.apply(command("viewportMode", ["layer": "2", "width": "320", "height": "200", "scale": "integer"]))
        #expect(scene.viewportMode(for: 2) == VTGViewportMode(layer: 2, width: 320, height: 200, scaleMode: .integer))

        scene.apply(command("viewportMode", ["layer": "2", "width": "0", "height": "200", "scale": "fit"]))
        #expect(scene.viewportMode(for: 2)?.scaleMode == .integer)

        scene.apply(command("viewportMode", ["layer": "2", "value": "native"]))
        #expect(scene.viewportMode(for: 2) == nil)
    }

    @Test func viewportScaleRequiresFixedViewportAndClearsWithMode() {
        let scene = VTGGraphicsScene()

        scene.apply(command("viewportScale", ["layer": "3", "scale": "2", "x": "10", "y": "20"]))
        #expect(scene.viewportScale(for: 3) == nil)

        scene.apply(command("viewportMode", ["layer": "3", "width": "640", "height": "400", "scale": "fit"]))
        scene.apply(command("viewportScale", ["layer": "3", "scale": "2", "x": "10", "y": "20"]))
        #expect(scene.viewportScale(for: 3) == VTGViewportScale(layer: 3, scale: 2, x: 10, y: 20))

        scene.apply(command("viewportScale", ["layer": "3", "scale": "-1", "x": "40", "y": "50"]))
        #expect(scene.viewportScale(for: 3)?.scale == 2)

        scene.apply(command("viewportMode", ["layer": "3", "mode": "native"]))
        #expect(scene.viewportMode(for: 3) == nil)
        #expect(scene.viewportScale(for: 3) == nil)
    }

    @Test func viewportTransformResolvesFitIntegerStretchAndOverrides() {
        let scene = VTGGraphicsScene()

        scene.apply(command("viewportMode", ["layer": "1", "width": "320", "height": "200", "scale": "fit"]))
        #expect(scene.viewportTransform(for: 1, canvasWidth: 800, canvasHeight: 600) == VTGViewportTransform(x: 0, y: 50, scaleX: 2.5, scaleY: 2.5, width: 800, height: 500))

        scene.apply(command("viewportMode", ["layer": "1", "width": "320", "height": "200", "scale": "integer"]))
        #expect(scene.viewportTransform(for: 1, canvasWidth: 800, canvasHeight: 600) == VTGViewportTransform(x: 80, y: 100, scaleX: 2, scaleY: 2, width: 640, height: 400))

        scene.apply(command("viewportMode", ["layer": "1", "width": "320", "height": "200", "scale": "stretch"]))
        #expect(scene.viewportTransform(for: 1, canvasWidth: 800, canvasHeight: 600) == VTGViewportTransform(x: 0, y: 0, scaleX: 2.5, scaleY: 3, width: 800, height: 600))

        scene.apply(command("viewportScale", ["layer": "1", "scale": "1.5", "x": "20", "y": "30"]))
        #expect(scene.viewportTransform(for: 1, canvasWidth: 800, canvasHeight: 600) == VTGViewportTransform(x: 20, y: 30, scaleX: 1.5, scaleY: 1.5, width: 480, height: 300))
    }

    @Test func viewportMousePositionAndHitRegionsMapToVirtualCoordinates() {
        let scene = VTGGraphicsScene()

        scene.apply(command("viewportMode", ["layer": "4", "width": "320", "height": "200", "scale": "integer"]))
        scene.apply(command("viewportScale", ["layer": "4", "scale": "2", "x": "40", "y": "50"]))
        scene.apply(command("layerScroll", ["layer": "4", "x": "10", "y": "5"]))
        scene.apply(command("hit", ["id": "virtualButton", "layer": "4", "x": "20", "y": "30", "w": "40", "h": "20"]))

        let virtual = scene.viewportMousePosition(at: VTGPoint(x: 100, y: 120), canvasWidth: 800, canvasHeight: 600)
        #expect(virtual == VTGViewportMousePosition(layer: 4, x: 20, y: 30))
        #expect(scene.hitRegion(at: VTGPoint(x: 100, y: 120), canvasWidth: 800, canvasHeight: 600)?.id == "virtualButton")
        #expect(scene.hitRegion(at: VTGPoint(x: 100, y: 120)) == nil)
    }

    @Test func layerClipCanBeSetClearedAndIgnoresInvalidSizes() {
        let scene = VTGGraphicsScene()

        scene.apply(command("clip", ["layer": "2", "x": "10", "y": "20", "w": "100", "h": "50"]))
        #expect(scene.clip(for: 2) == VTGLayerClip(x: 10, y: 20, width: 100, height: 50))

        scene.apply(command("clip", ["layer": "3", "x": "0", "y": "0", "w": "0", "h": "50"]))
        #expect(scene.clip(for: 3) == nil)

        scene.apply(command("clipClear", ["layer": "2"]))
        #expect(scene.clip(for: 2) == nil)
    }

    @Test func vectorSpriteUploadSharesSpritePlacementAndTransforms() {
        let scene = VTGGraphicsScene()

        scene.apply(command(
            "vectorSpriteUpload",
            ["id": "ship", "width": "40", "height": "30", "stroke": "#5eead4", "fill": "#07111d", "lineWidth": "2"],
            payload: "M 20 0 L 40 30 L 20 22 L 0 30 Z"
        ))
        scene.apply(command("sprite", ["id": "ship1", "image": "ship", "x": "10", "y": "20", "rotation": "5", "scale": "1.5", "anchorX": "0.25", "anchorY": "0.75"]))
        scene.apply(command("spriteTransform", ["id": "ship1", "x": "30", "y": "40", "rotation": "15", "scale": "2"]))
        scene.apply(command("spriteAnchor", ["id": "ship1", "anchorX": "2", "anchorY": "-1"]))

        #expect(scene.vectorSpriteAsset(id: "ship")?.width == 40)
        #expect(scene.primitives.count == 1)
        guard case .sprite(_, let assetID, let x, let y, let rotation, let scale, let anchorX, let anchorY) = scene.primitives[0] else {
            Issue.record("Expected retained vector sprite instance")
            return
        }
        #expect(assetID == "ship")
        #expect(x == 30)
        #expect(y == 40)
        #expect(rotation == 15)
        #expect(scale == 2)
        #expect(anchorX == 1)
        #expect(anchorY == 0)
    }

    @Test func spriteUploadsRejectInvalidIDsAndRespectAssetLimit() {
        let scene = VTGGraphicsScene()
        let payload = Data([1]).base64EncodedString()

        scene.apply(command("spriteUpload", ["id": "bad-id", "format": "png", "width": "1", "height": "1"], payload: payload))
        scene.apply(command("spriteUpload", ["id": "bad id", "format": "png", "width": "1", "height": "1"], payload: payload))
        scene.apply(command("spriteUpload", ["id": String(repeating: "a", count: 65), "format": "png", "width": "1", "height": "1"], payload: payload))
        #expect(scene.spriteAssets.isEmpty)

        for index in 0..<256 {
            scene.apply(command("spriteUpload", ["id": "s\(index)", "format": "png", "width": "1", "height": "1"], payload: payload))
        }
        #expect(scene.spriteAssets.count == 256)

        scene.apply(command("spriteUpload", ["id": "s256", "format": "png", "width": "1", "height": "1"], payload: payload))
        #expect(scene.spriteAsset(id: "s256") == nil)
    }

    @Test func duplicateSpriteUploadReplacesAssetAcrossBitmapAndVectorStores() {
        let scene = VTGGraphicsScene()
        let bitmapPayload = Data([1]).base64EncodedString()
        let replacementPayload = Data([2]).base64EncodedString()

        scene.apply(command("spriteUpload", ["id": "ship", "format": "png", "width": "10", "height": "20"], payload: bitmapPayload))
        #expect(scene.spriteAsset(id: "ship")?.width == 10)
        #expect(scene.spriteAsset(id: "ship")?.base64 == bitmapPayload)

        scene.apply(command("spriteUpload", ["id": "ship", "format": "jpeg", "width": "30", "height": "40"], payload: replacementPayload))
        #expect(scene.spriteAssets.count == 1)
        #expect(scene.spriteAsset(id: "ship")?.format == "jpeg")
        #expect(scene.spriteAsset(id: "ship")?.width == 30)
        #expect(scene.spriteAsset(id: "ship")?.base64 == replacementPayload)

        scene.apply(command(
            "vectorSpriteUpload",
            ["id": "ship", "width": "50", "height": "60", "stroke": "#5eead4"],
            payload: "M 0 0 L 50 30 L 0 60 Z"
        ))
        #expect(scene.spriteAsset(id: "ship") == nil)
        #expect(scene.vectorSpriteAsset(id: "ship")?.width == 50)

        scene.apply(command("spriteUpload", ["id": "ship", "format": "png", "width": "70", "height": "80"], payload: bitmapPayload))
        #expect(scene.vectorSpriteAsset(id: "ship") == nil)
        #expect(scene.spriteAsset(id: "ship")?.width == 70)
    }

    @Test func spriteRemoveAndClearRemoveAssetsAndDependentInstancesOnly() {
        let scene = VTGGraphicsScene()
        let payload = Data([1]).base64EncodedString()

        scene.apply(command("rect", ["id": "background", "x": "0", "y": "0", "w": "10", "h": "10"]))
        scene.apply(command("spriteUpload", ["id": "enemy", "format": "png", "width": "8", "height": "8"], payload: payload))
        scene.apply(command("spriteUpload", ["id": "player", "format": "png", "width": "8", "height": "8"], payload: payload))
        scene.apply(command("sprite", ["id": "enemy1", "image": "enemy", "x": "10", "y": "10", "layer": "2"]))
        scene.apply(command("sprite", ["id": "enemy2", "image": "enemy", "x": "20", "y": "10", "layer": "2"]))
        scene.apply(command("sprite", ["id": "player1", "image": "player", "x": "30", "y": "10", "layer": "3"]))

        scene.apply(command("spriteRemove", ["id": "enemy"]))

        #expect(scene.spriteAsset(id: "enemy") == nil)
        #expect(scene.spriteAsset(id: "player") != nil)
        #expect(scene.primitives.map(\.id).sorted() == ["background", "player1"])
        #expect(scene.layersByID["enemy1"] == nil)
        #expect(scene.layersByID["enemy2"] == nil)
        #expect(scene.layersByID["player1"] == 3)

        scene.apply(command("spriteClear"))

        #expect(scene.spriteAssets.isEmpty)
        #expect(scene.vectorSpriteAssets.isEmpty)
        #expect(scene.primitives.map(\.id) == ["background"])
        #expect(scene.layersByID["player1"] == nil)
    }

    private func command(
        _ name: String,
        _ parameters: [String: String] = [:],
        payload: String? = nil
    ) -> VectorTerminalGraphicsCommand {
        VectorTerminalGraphicsCommand(
            name: name,
            parameters: parameters,
            payload: payload
        )
    }
}
