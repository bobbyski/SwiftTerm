import Foundation
import Testing

@testable import SwiftTerm

/// `errorEvents` and `commandRejected`: a program that asks is told which of
/// its sprite commands were refused, and why.
@Suite("Refused sprite commands are reported")
struct VTGCommandRejectionTests {
    private let canvas = VTGCanvasSize(width: 640, height: 480)
    private let png = Data([1]).base64EncodedString()

    private func command(
        _ name: String,
        _ parameters: [String: String] = [:],
        payload: String? = nil
    ) -> VectorTerminalGraphicsCommand {
        VectorTerminalGraphicsCommand(name: name, parameters: parameters, payload: payload)
    }

    private func rejected(_ command: String, _ id: String, _ reason: String) -> String {
        "\u{1B}_VTG;commandRejected,command=\(command),id=\(id),reason=\(reason)\u{1B}\\"
    }

    private func reporting() -> VTGHostController {
        let controller = VTGHostController()
        _ = controller.process([command("errorEvents", ["enabled": "1"])], canvas: canvas)
        return controller
    }

    @Test("Off unless asked for: a program that never reads replies gets none")
    func offByDefault() {
        let controller = VTGHostController()
        let responses = controller.process(
            [command("spriteUpload", ["id": "bad.id", "format": "png", "width": "1", "height": "1"], payload: png)],
            canvas: canvas
        )
        #expect(responses.isEmpty)
    }

    @Test("Each refusal says which command, which id, and why")
    func everyReason() {
        let controller = reporting()
        let responses = controller.process([
            command("spriteUpload", ["id": "bad.id", "format": "png", "width": "1", "height": "1"], payload: png),
            command("spriteUpload", ["id": "garbled", "format": "png", "width": "1", "height": "1"], payload: "!!!"),
            command("spriteUpload", ["id": "gif", "format": "gif", "width": "1", "height": "1"], payload: png),
            command("spriteUpload", ["id": "flat", "format": "png", "width": "0", "height": "1"], payload: png),
            command("vectorSpriteUpload", ["id": "scribble", "width": "4", "height": "4"], payload: "nonsense"),
            command("spriteDataUpload", ["id": "nocolour", "width": "1", "height": "1", "palette": "#zz"], payload: "0"),
            command("spriteDataUpload", ["id": "short", "width": "2", "height": "2", "palette": "#ffffff"], payload: "0"),
            command("sprite", ["id": "ship1", "image": "nothere", "x": "1", "y": "1"]),
        ], canvas: canvas)
        #expect(responses == [
            rejected("spriteUpload", "bad.id", "badId"),
            rejected("spriteUpload", "garbled", "badData"),
            rejected("spriteUpload", "gif", "badFormat"),
            rejected("spriteUpload", "flat", "badSize"),
            rejected("vectorSpriteUpload", "scribble", "badData"),
            rejected("spriteDataUpload", "nocolour", "badPalette"),
            rejected("spriteDataUpload", "short", "badData"),
            rejected("sprite", "ship1", "unknownAsset"),
        ])
    }

    @Test("A full asset store says so")
    func limit() {
        let controller = reporting()
        let uploads = (0...256).map {
            command("spriteUpload", ["id": "s\($0)", "format": "png", "width": "1", "height": "1"], payload: png)
        }
        #expect(controller.process(uploads, canvas: canvas) == [rejected("spriteUpload", "s256", "limit")])
    }

    @Test("Accepted commands are not reported")
    func acceptedAreQuiet() {
        let controller = reporting()
        let responses = controller.process([
            command("spriteUpload", ["id": "player_ship", "format": "png", "width": "1", "height": "1"], payload: png),
            command("sprite", ["id": "p1", "image": "player_ship", "x": "1", "y": "1"]),
        ], canvas: canvas)
        #expect(responses.isEmpty)
    }

    @Test("Turning the replies on later brings up no old refusals")
    func noBacklog() {
        let controller = VTGHostController()
        _ = controller.process(
            [command("spriteUpload", ["id": "bad.id", "format": "png", "width": "1", "height": "1"], payload: png)],
            canvas: canvas
        )
        #expect(controller.process([command("errorEvents", ["enabled": "1"])], canvas: canvas).isEmpty)
    }

    @Test("Refusals inside a page are reported too")
    func pageMode() {
        let controller = reporting()
        _ = controller.process([command("pageBegin", ["id": "s"]), command("pageOpen", ["id": "p1"])], canvas: canvas)
        let responses = controller.process([
            command("spriteUpload", ["id": "bad.id", "format": "png", "width": "1", "height": "1"], payload: png),
            command("sprite", ["id": "ship1", "image": "nothere", "x": "1", "y": "1"]),
        ], canvas: canvas)
        #expect(responses.contains(rejected("spriteUpload", "bad.id", "badId")))
        #expect(responses.contains(rejected("sprite", "ship1", "unknownAsset")))
    }
}
