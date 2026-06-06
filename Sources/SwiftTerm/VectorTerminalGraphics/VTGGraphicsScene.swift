import Foundation

/// Retained scene model for VTG graphics primitives.
///
/// The terminal stream remains ANSI-compatible text. VTG commands update this
/// side scene, and terminal renderers consume the parts they can support.
public final class VTGGraphicsScene {
    public static let supportedLayerRange = VTGLayerModel.supportedRange

    public internal(set) var primitives: [VTGPrimitive] = []
    public internal(set) var spriteAssets: [String: VTGSpriteAsset] = [:]
    public internal(set) var vectorSpriteAssets: [String: VTGVectorSpriteAsset] = [:]
    public internal(set) var indexedSpriteAssets: [String: VTGIndexedSpriteAsset] = [:]
    public internal(set) var defaultLayer = VTGLayerModel.defaultDrawingLayer
    public internal(set) var layersByID: [String: Int] = [:]
    public internal(set) var layerOffsets: [Int: VTGLayerOffset] = [:]
    public internal(set) var layerClips: [Int: VTGLayerClip] = [:]
    public internal(set) var layerAlphas: [Int: Double] = [:]
    public internal(set) var viewportModes: [Int: VTGViewportMode] = [:]
    public internal(set) var viewportScales: [Int: VTGViewportScale] = [:]
    public internal(set) var hitRegions: [String: VTGHitRegion] = [:]
    var indexesByID: [String: Int] = [:]
    var nextHitOrder = 0
    let spriteAssetLimit = 256

    /// Primitives ordered by their current compositing layer.
    ///
    /// Layer -1 is under text, layer 0 is reserved for the future shared
    /// text/graphics plane, and layers 1-4 are overlays. This ordering gives
    /// apps deterministic z-order without claiming layer 0 is fully mingled
    /// with terminal text yet.
    public init() {}

    public var renderPrimitives: [VTGPrimitive] {
        primitives.enumerated()
            .sorted { lhs, rhs in
                let leftLayer = layer(for: lhs.element)
                let rightLayer = layer(for: rhs.element)
                if leftLayer == rightLayer {
                    return lhs.offset < rhs.offset
                }
                return leftLayer < rightLayer
            }
            .map(\.element)
    }

    /// Return primitives for one broad compositing plane while preserving the
    /// same deterministic order as `renderPrimitives`.
    ///
    /// Current overlay rendering still draws every retained primitive in Metal
    /// compatibility mode so demos keep behaving. Renderer-integrated spikes
    /// consume this method to pull one compositing plane into the terminal
    /// renderer without reinterpreting layer dictionaries themselves.
    public func renderPrimitives(in plane: VTGCompositingPlane) -> [VTGPrimitive] {
        renderPrimitives.filter { primitive in
            VTGLayerModel.compositingPlane(for: layer(for: primitive)) == plane
        }
    }

    /// Primitives assigned to layer -1, intended to render beneath glyphs.
    public var underTextPrimitives: [VTGPrimitive] {
        renderPrimitives(in: .underText)
    }

    /// Primitives assigned to layer 0, reserved for future true text/graphics
    /// mingling.
    public var textPlanePrimitives: [VTGPrimitive] {
        renderPrimitives(in: .textPlane)
    }

    /// Primitives assigned to overlay layers `1...4`.
    public var overlayPrimitives: [VTGPrimitive] {
        renderPrimitives(in: .overlay)
    }

    /// Return a copy of the current retained scene state.
    ///
    /// Offscreen frame support uses this as a graphics-only snapshot. The
    /// pending scene can then receive VTG mutations without exposing those
    /// changes to the visible renderer until the host commits the frame.
    public func makeSnapshot() -> VTGGraphicsScene {
        let snapshot = VTGGraphicsScene()
        snapshot.replaceContents(with: self)
        return snapshot
    }

    /// Replace this scene with another retained scene state.
    ///
    /// This copies public render state and internal bookkeeping. The primitive
    /// index is rebuilt from the copied primitive array so future updates still
    /// replace existing IDs instead of appending duplicates.
    public func replaceContents(with scene: VTGGraphicsScene) {
        primitives = scene.primitives
        spriteAssets = scene.spriteAssets
        vectorSpriteAssets = scene.vectorSpriteAssets
        indexedSpriteAssets = scene.indexedSpriteAssets
        defaultLayer = scene.defaultLayer
        layersByID = scene.layersByID
        layerOffsets = scene.layerOffsets
        layerClips = scene.layerClips
        layerAlphas = scene.layerAlphas
        viewportModes = scene.viewportModes
        viewportScales = scene.viewportScales
        hitRegions = scene.hitRegions
        nextHitOrder = scene.nextHitOrder
        rebuildIndexes()
    }

    /// Return an uploaded sprite asset for renderers/exporters.
    public func spriteAsset(id: String) -> VTGSpriteAsset? {
        spriteAssets[id]
    }

    /// Return an uploaded vector sprite asset for renderers/exporters.
    public func vectorSpriteAsset(id: String) -> VTGVectorSpriteAsset? {
        vectorSpriteAssets[id]
    }

    /// Return an uploaded palette-indexed sprite asset for renderers/exporters.
    public func indexedSpriteAsset(id: String) -> VTGIndexedSpriteAsset? {
        indexedSpriteAssets[id]
    }

    func rebuildIndexes() {
        indexesByID = Dictionary(uniqueKeysWithValues: primitives.enumerated().map { ($0.element.id, $0.offset) })
    }

    static func isValidIdentifier(_ value: String) -> Bool {
        guard value.isEmpty == false, value.count <= 64 else {
            return false
        }
        return value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber)
        }
    }
}
