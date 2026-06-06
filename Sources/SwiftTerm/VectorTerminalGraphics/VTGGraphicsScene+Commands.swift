import Foundation

/// Command dispatch and retained primitive list mutation for the VTG scene.
extension VTGGraphicsScene {
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
            clear()
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
        case "spriteDataUpload":
            uploadIndexedSprite(command)
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
}
