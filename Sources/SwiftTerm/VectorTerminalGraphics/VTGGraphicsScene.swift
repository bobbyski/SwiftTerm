import Foundation

/// Retained scene model for VTG overlay primitives.
///
/// The terminal stream remains ANSI-compatible text. VTG commands update this
/// side scene, and `VTGOverlayView` renders it on top of the terminal surface.
public final class VTGGraphicsScene {
    public static let supportedLayerRange = VTGLayerModel.supportedRange

    public internal(set) var primitives: [VTGPrimitive] = []
    public internal(set) var spriteAssets: [String: VTGSpriteAsset] = [:]
    public internal(set) var vectorSpriteAssets: [String: VTGVectorSpriteAsset] = [:]
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
    /// Layer 0 is reserved for the future shared text/graphics plane. Until VTG
    /// moves into SwiftTerm, all layers still render in the overlay view; this
    /// ordering gives apps deterministic z-order without claiming layer 0 is
    /// fully mingled with terminal text yet.
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

    /// Apply one parsed VTG command to the retained primitive list.
    public func apply(_ command: VectorTerminalGraphicsCommand) {
        switch command.name {
        case "begin", "present", "capabilities?":
            break
        case "defaultLayer":
            defaultLayer = command.layerValue(default: defaultLayer)
        case "layer":
            setPrimitiveLayer(command)
        case "layerScroll":
            setLayerScroll(command)
        case "layerAlpha":
            setLayerAlpha(command)
        case "viewportMode":
            setViewportMode(command)
        case "viewportScale":
            setViewportScale(command)
        case "clip":
            setLayerClip(command)
        case "clipClear":
            clearLayerClip(command)
        case "hit":
            upsertHitRegion(command)
        case "hitClear":
            clearHitRegion(command)
        case "clear":
            primitives.removeAll()
            spriteAssets.removeAll()
            vectorSpriteAssets.removeAll()
            indexesByID.removeAll()
            layersByID.removeAll()
            layerOffsets.removeAll()
            layerClips.removeAll()
            layerAlphas.removeAll()
            viewportModes.removeAll()
            viewportScales.removeAll()
            hitRegions.removeAll()
            defaultLayer = VTGLayerModel.defaultDrawingLayer
        case "delete":
            if let id = command.parameters["id"] {
                remove(id: id)
            }
        case "pixel":
            upsert(parsePixel(command), command: command)
        case "line":
            upsert(parseLine(command), command: command)
        case "draw":
            upsert(parseDraw(command), command: command)
        case "curve":
            upsert(parseCurve(command), command: command)
        case "triangle":
            upsert(parseTriangle(command), command: command)
        case "path":
            upsert(parsePath(command), command: command)
        case "rect":
            upsert(parseRect(command), command: command)
        case "circle":
            upsert(parseCircle(command), command: command)
        case "ellipse":
            upsert(parseEllipse(command), command: command)
        case "text":
            upsert(parseText(command), command: command)
        case "image":
            upsert(parseImage(command), command: command)
        case "spriteUpload":
            uploadSprite(command)
        case "vectorSpriteUpload":
            uploadVectorSprite(command)
        case "sprite":
            upsert(parseSprite(command), command: command)
        case "spriteMove":
            transformSprite(command, updates: [.position])
        case "spriteRotate":
            transformSprite(command, updates: [.rotation])
        case "spriteTransform":
            transformSprite(command, updates: [.position, .rotation, .scale, .anchor])
        case "spriteAnchor":
            transformSprite(command, updates: [.anchor])
        case "spriteRemove":
            if let id = command.parameters["id"] {
                removeSpriteAsset(id: id)
            }
        case "spriteClear":
            removeAllSpriteAssets()
        default:
            break
        }
    }

    func upsert(_ primitive: VTGPrimitive?, command: VectorTerminalGraphicsCommand) {
        guard let primitive else {
            return
        }
        layersByID[primitive.id] = command.layerValue(default: layersByID[primitive.id] ?? defaultLayer)
        if let index = indexesByID[primitive.id] {
            primitives[index] = primitive
        } else {
            indexesByID[primitive.id] = primitives.count
            primitives.append(primitive)
        }
    }

    func remove(id: String) {
        guard let index = indexesByID[id] else {
            return
        }
        primitives.remove(at: index)
        layersByID.removeValue(forKey: id)
        // Removing from an array shifts later indexes, so rebuild the small
        // lookup table rather than trying to patch every affected index.
        indexesByID = Dictionary(uniqueKeysWithValues: primitives.enumerated().map { ($0.element.id, $0.offset) })
    }

    func setPrimitiveLayer(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              indexesByID[id] != nil else {
            return
        }
        layersByID[id] = command.layerValue(default: layersByID[id] ?? defaultLayer)
    }

    /// Return an uploaded sprite asset for renderers/exporters.
    public func spriteAsset(id: String) -> VTGSpriteAsset? {
        spriteAssets[id]
    }

    /// Return an uploaded vector sprite asset for renderers/exporters.
    public func vectorSpriteAsset(id: String) -> VTGVectorSpriteAsset? {
        vectorSpriteAssets[id]
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
