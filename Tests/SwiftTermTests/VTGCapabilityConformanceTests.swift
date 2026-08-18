//
//  VTGCapabilityConformanceTests.swift
//
//  The capability string is a promise to consumers: a client asks what this
//  terminal can do and then emits only what was advertised. A token that
//  nothing implements turns that protection into a silently blank region — the
//  exact failure a consumer queries capabilities to avoid.
//
//  These tests make the promise mechanical rather than maintained by hand.
//

import Foundation
import Testing

@testable import SwiftTerm

@Suite("VTG capability conformance")
struct VTGCapabilityConformanceTests {

    /// Every advertised command is handled by the scene, or is declared as one
    /// the host controller answers. A command implemented nowhere fails here.
    @Test("Nothing is advertised that nothing handles")
    func advertisedCommandsAreHandled() {
        let scene = VTGGraphicsScene()
        let sessionOwned = Set(VTGResponseEncoder.sessionCommands)
        var unhandled: [String] = []

        for name in VTGResponseEncoder.defaultCommands where !sessionOwned.contains(name) {
            // Parameters are deliberately absent: this asks whether the command
            // is *known*, not whether a particular payload is valid.
            if !scene.apply(VectorTerminalGraphicsCommand(name: name)) {
                unhandled.append(name)
            }
        }

        #expect(unhandled.isEmpty, "advertised but unhandled: \(unhandled.joined(separator: ", "))")
    }

    /// Session-owned commands must actually be advertised, and must not also be
    /// claimed by the scene — otherwise the split is fiction.
    @Test("The session-owned split is real")
    func sessionCommandsArePartitioned() {
        let advertised = Set(VTGResponseEncoder.defaultCommands)
        let scene = VTGGraphicsScene()

        for name in VTGResponseEncoder.sessionCommands {
            #expect(advertised.contains(name),
                    "'\(name)' is declared session-owned but is not advertised")
            #expect(!scene.apply(VectorTerminalGraphicsCommand(name: name)),
                    "'\(name)' is declared session-owned but the scene also handles it")
        }
    }

    /// A command nobody implements must report itself as unhandled, or the test
    /// above proves nothing.
    @Test("An unknown command is reported as unhandled")
    func unknownCommandsAreRejected() {
        let scene = VTGGraphicsScene()
        #expect(!scene.apply(VectorTerminalGraphicsCommand(name: "definitelyNotAVTGCommand")))
    }

    /// Capability tokens describe primitives; the primitives must be commands.
    @Test("Advertised primitives are themselves advertised commands")
    func primitivesAreCommands() {
        let commands = Set(VTGResponseEncoder.defaultCommands)
        for primitive in VTGResponseEncoder.defaultPrimitives {
            #expect(commands.contains(primitive),
                    "primitive '\(primitive)' is advertised but is not a command")
        }
    }

    /// Under-text is a narrower set by design; it must stay a real subset.
    @Test("Under-text primitives are a subset of the full primitive set")
    func underTextIsASubset() {
        let all = Set(VTGResponseEncoder.defaultPrimitives)
        for primitive in VTGResponseEncoder.defaultUnderTextPrimitives {
            #expect(all.contains(primitive),
                    "under-text primitive '\(primitive)' is not in the primitive set")
        }
    }

    /// Sprite features are only meaningful if the sprite commands exist.
    @Test("Sprite features correspond to sprite commands")
    func spriteFeaturesHaveCommands() {
        let commands = Set(VTGResponseEncoder.defaultCommands)
        let sprites = Set(VTGResponseEncoder.defaultSpriteFeatures)

        if sprites.contains("move") { #expect(commands.contains("spriteMove")) }
        if sprites.contains("rotate") { #expect(commands.contains("spriteRotate")) }
        if sprites.contains("bitmap") { #expect(commands.contains("spriteUpload")) }
        if sprites.contains("vector") { #expect(commands.contains("vectorSpriteUpload")) }
        if sprites.contains("indexed") { #expect(commands.contains("spriteDataUpload")) }
        #expect(commands.contains("sprite"))
    }

    /// Nothing may be advertised as planned *and* implemented at once.
    @Test("Planned commands are not also advertised as available")
    func plannedAndAvailableDoNotOverlap() {
        let commands = Set(VTGResponseEncoder.defaultCommands)
        for planned in VTGResponseEncoder.plannedCommands {
            #expect(!commands.contains(planned),
                    "'\(planned)' is advertised as both planned and available")
        }
    }
}
