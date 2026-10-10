import Foundation
import Testing

@testable import SwiftTerm

/// Uploaded sprite assets outlive `clear`: a program that clears the screen
/// and places its sprites again must find them there. Only `spriteRemove`,
/// `spriteClear` or a new program remove them.
@Suite("Sprite assets survive clear")
struct VTGSpriteAssetLifetimeTests {
    private let canvas = VTGCanvasSize(width: 640, height: 480)
    private let png = Data([1]).base64EncodedString()

    private func command(
        _ name: String,
        _ parameters: [String: String] = [:],
        payload: String? = nil
    ) -> VectorTerminalGraphicsCommand {
        VectorTerminalGraphicsCommand(name: name, parameters: parameters, payload: payload)
    }

    private var uploads: [VectorTerminalGraphicsCommand] {
        [
            command("spriteUpload", ["id": "ship", "format": "png", "width": "8", "height": "8"], payload: png),
            command("vectorSpriteUpload", ["id": "rock", "width": "4", "height": "4"], payload: "M 0 0 L 4 4 Z"),
            command("spriteDataUpload", ["id": "dot", "width": "1", "height": "1", "palette": "#ffffff"], payload: "0"),
        ]
    }

    @Test("clear removes the drawing and the placed sprites, and keeps the pictures")
    func clearKeepsAssets() {
        let scene = VTGGraphicsScene()
        uploads.forEach { scene.apply($0) }
        scene.apply(command("rect", ["id": "box", "x": "0", "y": "0", "w": "4", "h": "4"]))
        scene.apply(command("sprite", ["id": "ship1", "image": "ship", "x": "1", "y": "1"]))

        scene.apply(command("clear"))

        #expect(scene.primitives.isEmpty)
        #expect(scene.spriteAsset(id: "ship") != nil)
        #expect(scene.vectorSpriteAsset(id: "rock") != nil)
        #expect(scene.indexedSpriteAsset(id: "dot") != nil)

        scene.apply(command("sprite", ["id": "ship1", "image": "ship", "x": "2", "y": "2"]))
        #expect(scene.primitive(id: "ship1") != nil, "placed again after the clear")
    }

    @Test("spriteClear still removes the pictures")
    func spriteClearRemovesAssets() {
        let scene = VTGGraphicsScene()
        uploads.forEach { scene.apply($0) }
        scene.apply(command("spriteClear"))
        #expect(scene.uploadedSpriteAssetCount == 0)
    }

    @Test("A page's clear keeps the page's pictures")
    func pageClearKeepsAssets() throws {
        let controller = VTGHostController()
        _ = controller.process([command("pageBegin", ["id": "s"]), command("pageOpen", ["id": "p1"])] + uploads + [
            command("sprite", ["id": "ship1", "image": "ship", "x": "1", "y": "1"]),
            command("clear"),
        ], canvas: canvas)
        let page = try #require(controller.pageMode?.targetPage)
        let layer = try #require(page.layer(id: "1"))
        #expect(layer.scene.primitives.isEmpty)
        #expect(layer.scene.spriteAsset(id: "ship") != nil)

        _ = controller.process([command("sprite", ["id": "ship1", "image": "ship", "x": "2", "y": "2"])], canvas: canvas)
        #expect(layer.scene.primitive(id: "ship1") != nil, "placed again after the clear")
    }

    @Test("Switching raster mode keeps the pictures")
    func rasterModeKeepsAssets() {
        let controller = VTGHostController()
        _ = controller.process(uploads + [command("rasterMode", ["enabled": "1"])], canvas: canvas)
        #expect(controller.scene.spriteAsset(id: "ship") != nil)
        _ = controller.process([command("rasterMode", ["enabled": "0"])], canvas: canvas)
        #expect(controller.scene.spriteAsset(id: "ship") != nil)
    }

    @Test("A new program starts with no pictures")
    func newSessionDropsAssets() {
        let controller = VTGHostController()
        _ = controller.process(uploads, canvas: canvas)
        controller.resetSession()
        #expect(controller.scene.uploadedSpriteAssetCount == 0)
    }
}
