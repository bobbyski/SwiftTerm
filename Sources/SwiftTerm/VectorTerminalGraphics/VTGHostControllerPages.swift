import Foundation

/// VTG Page Mode command handling for `VTGHostController`.
///
/// Nothing here is reachable until a program sends `pageBegin`. Until then the
/// only additions a program can observe are the new query commands, which
/// older hosts ignore, and the rich-text measurement queries.
extension VTGHostController {
    /// Page mode as the renderer sees it: what is on screen now.
    public var pageMode: VTGPageModeState? {
        pageModeState
    }

    /// Page mode as commands see it — the frame's copy while one is open.
    var activePageMode: VTGPageModeState? {
        framePageModeState ?? pageModeState
    }

    public var isPageModeActive: Bool {
        pageModeState != nil
    }

    /// Commands answered here rather than by a scene.
    static let extendedSessionCommands: Set<String> = [
        "pageBegin", "pageEnd", "pageTarget",
        "pageOpen", "pageShow", "pageHide", "pageSelect", "pageClose", "pageClear",
        "pageResize", "pageBackground", "pageAlpha", "pageViewport",
        "pageScroll", "pageScrollBy", "pageScrollTo", "pageScrollMode",
        "pageLayerAdd", "pageLayerSelect", "pageLayerClear", "pageLayerRemove",
        "pageLayerOrder", "pageLayerAlpha", "pageLayerVisible", "pageLayerOffset",
        "pageLayerCache", "pageLayerCopy",
        "page?", "pageState?", "pageLimits?", "windowCanvas?",
        "textMeasure?", "fonts?"
    ]

    /// Scene commands that follow the draw target into a page. Queries and
    /// session commands never do, so routing cannot create layers as a side
    /// effect of, say, `mouseEvents`.
    static let pageRoutableCommands: Set<String> = [
        "clear", "delete", "defaultLayer", "layer", "layerScroll", "layerAlpha",
        "layerAnchor", "viewportMode", "viewportScale", "clip", "clipClear",
        "hit", "hitClear", "pixel", "clearRect", "line", "draw", "curve",
        "triangle", "path", "rect", "circle", "ellipse", "text", "image",
        "spriteUpload", "vectorSpriteUpload", "spriteDataUpload", "sprite",
        "spriteMove", "spriteRotate", "spriteAnchor", "spriteTransform",
        "spriteRemove", "spriteClear", "styledText", "attrText", "textBox"
    ]

    private static let assetUploadCommands: Set<String> = [
        "spriteUpload", "vectorSpriteUpload", "spriteDataUpload"
    ]

    // MARK: - Dispatch

    /// Handle a page-mode, text-measurement, or font command. `nil` when the
    /// command is none of those.
    func handleExtendedCommand(
        _ command: VectorTerminalGraphicsCommand,
        canvas: VTGCanvasSize,
        glyphSize: (width: Double, height: Double)?
    ) -> [String]? {
        guard Self.extendedSessionCommands.contains(command.name) else {
            return nil
        }
        switch command.name {
        case "windowCanvas?":
            return [VTGResponseEncoder.canvasResponse(commandName: "windowCanvas", canvas: canvas)]
        case "textMeasure?":
            return [textMeasureResponse(command)]
        case "fonts?":
            return [fontsResponse()]
        case "page?":
            return [pageQueryResponse()]
        case "pageBegin":
            return beginPageMode(command)
        default:
            break
        }
        guard let mode = activePageMode else {
            return [pageRejected(command, reason: "notInPageMode")]
        }
        pageScopeTouched = true
        switch command.name {
        case "pageEnd":
            return endPageMode(reason: "app", canvas: canvas)
        case "pageTarget":
            mode.drawsToBase = command.parameters["scene"] == "base"
            return []
        case "pageOpen":
            return openPage(command, mode: mode, canvas: canvas, glyphSize: glyphSize)
        case "pageShow":
            return showPage(command, mode: mode)
        case "pageHide":
            guard let page = mode.visiblePage else {
                return []
            }
            mode.visibleSlot = nil
            return [pageEvent("pageHidden", ("id", page.id))]
        case "pageSelect":
            guard let page = namedPage(command, mode: mode, required: true) else {
                return [pageRejected(command, reason: "unknownPage")]
            }
            mode.targetSlot = page.slot
            mode.drawsToBase = false
            return []
        case "pageClose":
            return closePage(command, mode: mode)
        case "pageState?":
            guard let page = namedPage(command, mode: mode) else {
                return [pageRejected(command, reason: "unknownPage")]
            }
            return [pageStateResponse(page, mode: mode)]
        case "pageLimits?":
            return [pageLimitsResponse(mode.targetPage, canvas: canvas)]
        default:
            break
        }

        guard let page = namedPage(command, mode: mode, key: command.name.hasPrefix("pageLayer") ? "page" : "id") else {
            return [pageRejected(command, reason: mode.targetPage == nil ? "noPage" : "unknownPage")]
        }
        switch command.name {
        case "pageClear":
            return clearPage(command, page: page)
        case "pageResize":
            if let width = command.optionalDouble("w"), width > 0 {
                page.width = min(width, page.maxWidth)
            }
            if let height = command.optionalDouble("h"), height > 0 {
                page.height = min(height, page.maxHeight)
            }
            page.clampScroll(canvas: canvas)
            return [pageResizedEvent(page, reason: "app")]
        case "pageBackground":
            page.background = command.color("bg")
            return []
        case "pageAlpha":
            page.alpha = min(1, max(0, command.double("alpha", default: page.alpha)))
            return []
        case "pageViewport":
            if command.parameters["value"] == "full" {
                page.viewport = nil
            } else {
                let width = command.double("w", default: command.double("width"))
                let height = command.double("h", default: command.double("height"))
                guard width > 0, height > 0 else {
                    return [pageError(page.id, reason: "badParam")]
                }
                page.viewport = VTGLayerClip(x: command.double("x"), y: command.double("y"), width: width, height: height)
            }
            page.clampScroll(canvas: canvas)
            return []
        case "pageScroll":
            page.scrollX = command.double("x", default: page.scrollX)
            page.scrollY = command.double("y", default: page.scrollY)
            page.clampScroll(canvas: canvas)
            return []
        case "pageScrollBy":
            page.scrollX += command.double("dx")
            page.scrollY += command.double("dy")
            page.clampScroll(canvas: canvas)
            return []
        case "pageScrollTo":
            switch command.parameters["anchor"] {
            case "top": page.scrollY = 0
            case "bottom": page.scrollY = .greatestFiniteMagnitude
            case "left": page.scrollX = 0
            case "right": page.scrollX = .greatestFiniteMagnitude
            default: return [pageError(page.id, reason: "badParam")]
            }
            page.clampScroll(canvas: canvas)
            return []
        case "pageScrollMode":
            mode.userScrollEnabled = Self.isTruthy(command.parameters["user"])
            mode.userScrollAxis = command.parameters["axis"].flatMap(VTGPageScrollAxis.init(rawValue:)) ?? .both
            return []
        default:
            return handleLayerCommand(command, page: page, mode: mode)
        }
    }

    // MARK: - Session

    private func beginPageMode(_ command: VectorTerminalGraphicsCommand) -> [String] {
        guard pageModeState == nil else {
            return [pageRejected(command, reason: "nested")]
        }
        let requested = command.parameters["id"] ?? ""
        let sessionID = VTGGraphicsScene.isValidTextIdentifier(requested) ? requested : "vpm"
        let stacking = command.parameters["over"].flatMap(VTGPageStacking.init(rawValue:)) ?? .all
        pageModeState = VTGPageModeState(sessionID: sessionID, stacking: stacking)
        // Entering page mode inside a frame is odd but legal; the frame then
        // works in a copy like any other page command.
        if pendingFrame != nil {
            framePageModeState = pageModeState?.copyForFrame()
        }
        pageScopeTouched = true
        return [pageEvent("pageBegan", ("id", sessionID), ("version", "1"), ("slots", "2"))]
    }

    /// Leave page mode and free both buffers.
    ///
    /// Before reporting `pageEnded`, a resize subscriber is told the real
    /// window size again: page mode reports the page viewport as the canvas,
    /// and a program that only listens for `resize` must be able to resync
    /// without knowing page mode existed.
    func endPageMode(reason: String, canvas: VTGCanvasSize?) -> [String] {
        guard let mode = pageModeState else {
            return []
        }
        pageModeState = nil
        framePageModeState = nil
        pageScopeTouched = false
        var responses: [String] = []
        if let canvas, sendsResizeEvents, canvas.width > 0, canvas.height > 0 {
            lastReportedCanvas = canvas
            responses.append(VTGResponseEncoder.resize(canvas: canvas))
        }
        responses.append(pageEvent("pageEnded", ("id", mode.sessionID), ("reason", reason)))
        return responses
    }

    // MARK: - Buffers

    private func openPage(
        _ command: VectorTerminalGraphicsCommand,
        mode: VTGPageModeState,
        canvas: VTGCanvasSize,
        glyphSize: (width: Double, height: Double)?
    ) -> [String] {
        guard let id = command.parameters["id"], VTGGraphicsScene.isValidTextIdentifier(id) else {
            return [pageRejected(command, reason: "badParam")]
        }
        // The non-visible slot; with nothing visible, the one that is not the
        // current draw target; the very first page, A.
        let slot: VTGPageSlot
        if let visible = mode.visibleSlot {
            slot = visible == .a ? .b : .a
        } else if let target = mode.targetSlot {
            slot = target == .a ? .b : .a
        } else {
            slot = .a
        }

        var responses: [String] = []
        let replaced = mode.page(in: slot)
        if let replaced {
            responses.append(contentsOf: detachBorrowers(of: replaced, mode: mode))
        }

        let windowWidth = Double(max(1, canvas.width))
        let windowHeight = Double(max(1, canvas.height))
        let width = pageAxis(command, pixelKey: "w", cellKey: "cols", window: windowWidth, cell: glyphSize?.width, growsByDefault: false)
        let height = pageAxis(command, pixelKey: "h", cellKey: "rows", window: windowHeight, cell: glyphSize?.height, growsByDefault: true)
        var growsWidth = width.grows
        var growsHeight = height.grows
        switch command.parameters["grow"] {
        case "none": (growsWidth, growsHeight) = (false, false)
        case "w": (growsWidth, growsHeight) = (true, false)
        case "h": (growsWidth, growsHeight) = (false, true)
        case "wh": (growsWidth, growsHeight) = (true, true)
        default: break
        }
        let maxWidth = max(width.size, command.optionalDouble("maxW").flatMap { $0 > 0 ? $0 : nil } ?? windowWidth * 16)
        let maxHeight = max(height.size, command.optionalDouble("maxH").flatMap { $0 > 0 ? $0 : nil } ?? windowHeight * 16)

        let page = VTGPage(
            id: id,
            slot: slot,
            width: width.size,
            height: height.size,
            growsWidth: growsWidth,
            growsHeight: growsHeight,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            padding: max(0, command.double("padding")),
            background: command.color("bg"),
            resizePolicy: command.parameters["resize"].flatMap(VTGPageResizePolicy.init(rawValue:)) ?? .auto,
            widthFromWindow: width.fromWindow,
            heightFromWindow: height.fromWindow,
            textStyles: scene.textStyles
        )
        mode.slots[slot.index] = page
        mode.targetSlot = slot
        mode.drawsToBase = false
        responses.append(pageEvent(
            "pageOpened",
            ("id", id),
            ("slot", slot.rawValue),
            ("w", Self.pageNumber(page.width)),
            ("h", Self.pageNumber(page.height)),
            ("growW", growsWidth ? "1" : "0"),
            ("growH", growsHeight ? "1" : "0"),
            ("replaced", replaced?.id ?? "none")
        ))
        return responses
    }

    /// Resolve one axis of `pageOpen`: pixels, then cells, then the window.
    private func pageAxis(
        _ command: VectorTerminalGraphicsCommand,
        pixelKey: String,
        cellKey: String,
        window: Double,
        cell: Double?,
        growsByDefault: Bool
    ) -> (size: Double, grows: Bool, fromWindow: Bool) {
        if let pixels = command.optionalDouble(pixelKey) {
            if pixels < 0 {
                return (window, true, true)
            }
            if pixels > 0 {
                return (pixels, false, false)
            }
        }
        if let cells = command.optionalDouble(cellKey) {
            if cells < 0 {
                return (window, true, true)
            }
            if cells > 0, let cell, cell > 0 {
                return (cells * cell, false, false)
            }
        }
        return (window, growsByDefault, true)
    }

    private func showPage(_ command: VectorTerminalGraphicsCommand, mode: VTGPageModeState) -> [String] {
        guard let page = namedPage(command, mode: mode) else {
            return [pageRejected(command, reason: mode.targetPage == nil ? "noPage" : "unknownPage")]
        }
        mode.visibleSlot = page.slot
        if Self.isTruthy(command.parameters["select"]) {
            mode.targetSlot = page.slot
            mode.drawsToBase = false
        }
        return [pageEvent("pageShown", ("id", page.id), ("slot", page.slot.rawValue))]
    }

    private func closePage(_ command: VectorTerminalGraphicsCommand, mode: VTGPageModeState) -> [String] {
        guard let page = namedPage(command, mode: mode) else {
            return [pageRejected(command, reason: "unknownPage")]
        }
        mode.slots[page.slot.index] = nil
        if mode.visibleSlot == page.slot {
            mode.visibleSlot = nil
        }
        if mode.targetSlot == page.slot {
            mode.targetSlot = nil
        }
        return detachBorrowers(of: page, mode: mode) + [pageEvent("pageClosed", ("id", page.id))]
    }

    private func clearPage(_ command: VectorTerminalGraphicsCommand, page: VTGPage) -> [String] {
        if let layerID = command.parameters["layer"] {
            guard let layer = page.layer(id: layerID) else {
                return [pageError(page.id, reason: "unknownLayer")]
            }
            guard !layer.isReadOnly else {
                return [pageError(page.id, reason: "readOnlyLayer")]
            }
            clearContent(of: layer, in: page)
            return []
        }
        if Self.isTruthy(command.parameters["layers"]) {
            page.layers.removeAll()
            page.selectedLayerID = VTGPage.defaultLayerID
            return []
        }
        for layer in page.layers where !layer.isReadOnly {
            clearContent(of: layer, in: page)
        }
        return []
    }

    /// Empty a layer's primitives while keeping its settings and the page's
    /// uploaded sprite assets.
    private func clearContent(of layer: VTGPageLayer, in page: VTGPage) {
        layer.scene.clear()
        page.syncAssets(into: layer.scene)
    }

    /// A page is going away. Layers other pages borrowed from it keep the last
    /// content as their own copy; each borrower is told.
    private func detachBorrowers(of source: VTGPage, mode: VTGPageModeState) -> [String] {
        var responses: [String] = []
        for page in mode.pages where page !== source {
            for layer in page.layers where layer.sourcePageID == source.id {
                layer.sourcePageID = nil
                layer.sourceLayerID = nil
                responses.append(pageError(page.id, reason: "sourceClosed", ("layer", layer.id)))
            }
        }
        return responses
    }

    // MARK: - Layers

    private func handleLayerCommand(
        _ command: VectorTerminalGraphicsCommand,
        page: VTGPage,
        mode: VTGPageModeState
    ) -> [String] {
        guard let layerID = command.parameters["id"], VTGGraphicsScene.isValidTextIdentifier(layerID) else {
            return [pageRejected(command, reason: "badParam")]
        }
        if command.name == "pageLayerCopy" {
            return copyLayer(command, into: page, as: layerID, mode: mode)
        }
        if command.name == "pageLayerAdd" || command.name == "pageLayerSelect" {
            guard let layer = page.ensureLayer(id: layerID, z: command.optionalDouble("z")) else {
                return [pageLimitError(page, "layers")]
            }
            if command.name == "pageLayerSelect" {
                page.selectedLayerID = layer.id
                return []
            }
            configure(layer, from: command)
            return []
        }
        guard let layer = page.layer(id: layerID) else {
            return [pageError(page.id, reason: "unknownLayer", ("layer", layerID))]
        }
        switch command.name {
        case "pageLayerClear":
            guard !layer.isReadOnly else {
                return [pageError(page.id, reason: "readOnlyLayer", ("layer", layerID))]
            }
            clearContent(of: layer, in: page)
        case "pageLayerRemove":
            page.removeLayer(id: layerID)
        default:
            configure(layer, from: command)
        }
        return []
    }

    /// Apply whichever layer settings a command carries.
    private func configure(_ layer: VTGPageLayer, from command: VectorTerminalGraphicsCommand) {
        if let z = command.optionalDouble("z") {
            layer.z = z
        }
        if let alpha = command.optionalDouble("alpha") {
            layer.alpha = min(1, max(0, alpha))
        }
        if let visible = command.parameters["visible"] {
            layer.isVisible = Self.isTruthy(visible)
        }
        if command.parameters["x"] != nil || command.parameters["y"] != nil {
            layer.offset = VTGLayerOffset(
                x: command.double("x", default: layer.offset.x),
                y: command.double("y", default: layer.offset.y)
            )
        }
        if let scroll = command.parameters["scroll"].flatMap(VTGPageLayerScrollMode.init(rawValue:)) {
            layer.scrollMode = scroll
        }
        if let cache = command.parameters["cache"] {
            layer.cacheHint = Self.isTruthy(cache)
        }
    }

    private func copyLayer(
        _ command: VectorTerminalGraphicsCommand,
        into page: VTGPage,
        as layerID: String,
        mode: VTGPageModeState
    ) -> [String] {
        guard let sourcePage = command.parameters["from"].flatMap(mode.page(id:)) ?? (command.parameters["from"] == nil ? page : nil),
              let sourceLayer = sourcePage.layer(id: command.parameters["layer"] ?? layerID) else {
            return [pageError(page.id, reason: "unknownLayer")]
        }
        let byReference = command.parameters["mode"] != "copy"
        let layer = VTGPageLayer(
            id: layerID,
            z: command.optionalDouble("z") ?? sourceLayer.z,
            order: page.layer(id: layerID)?.order ?? page.nextLayerOrder,
            scene: byReference ? sourceLayer.scene : sourceLayer.scene.makeSnapshot()
        )
        if byReference {
            // A reference to a reference points at the original owner.
            layer.sourcePageID = sourceLayer.sourcePageID ?? sourcePage.id
            layer.sourceLayerID = sourceLayer.sourceLayerID ?? sourceLayer.id
        }
        layer.scrollMode = sourceLayer.scrollMode
        configure(layer, from: VectorTerminalGraphicsCommand(
            name: command.name,
            parameters: command.parameters.filter { ["alpha", "visible", "x", "y", "scroll", "cache"].contains($0.key) }
        ))
        guard page.insert(layer) else {
            return [pageLimitError(page, "layers")]
        }
        return []
    }

    // MARK: - Drawing into a page

    /// Send an ordinary scene command to the target page. `nil` when the
    /// command belongs to the base scene as usual.
    func routeDrawingToPage(_ command: VectorTerminalGraphicsCommand) -> [String]? {
        guard let mode = activePageMode,
              !mode.drawsToBase,
              Self.pageRoutableCommands.contains(command.name) else {
            return nil
        }
        guard let page = mode.targetPage else {
            return [pageError(mode.sessionID, reason: "noPage", ("command", command.name))]
        }
        pageScopeTouched = true

        switch command.name {
        case "clear":
            // Everything the page owns; borrowed layers belong to their owner.
            page.assets.clear()
            for layer in page.layers where !layer.isReadOnly {
                layer.scene.clear()
            }
            return []
        case "delete":
            if let id = command.parameters["id"] {
                for layer in page.layers where !layer.isReadOnly {
                    layer.scene.remove(id: id)
                }
            }
            return []
        case "defaultLayer":
            let layerID = command.parameters["layer"] ?? command.parameters["value"] ?? VTGPage.defaultLayerID
            guard page.ensureLayer(id: layerID) != nil else {
                return [pageLimitError(page, "layers")]
            }
            page.selectedLayerID = layerID
            return []
        case "layer":
            return movePrimitive(command, in: page)
        case "layerAlpha", "layerScroll":
            let layerID = command.parameters["layer"] ?? page.selectedLayerID
            guard let layer = page.ensureLayer(id: layerID) else {
                return [pageLimitError(page, "layers")]
            }
            if command.name == "layerAlpha" {
                layer.alpha = min(1, max(0, command.double("alpha", default: layer.alpha)))
            } else {
                layer.offset = VTGLayerOffset(x: command.double("x"), y: command.double("y"))
            }
            return []
        case "layerAnchor":
            // Pages are documents of their own; text anchoring does not apply.
            return []
        case _ where Self.assetUploadCommands.contains(command.name):
            page.assets.apply(command)
            page.syncAssetsIntoOwnLayers()
            return []
        case "spriteRemove", "spriteClear":
            page.assets.apply(command)
            for layer in page.layers where !layer.isReadOnly {
                layer.scene.apply(command)
            }
            return []
        default:
            break
        }

        let layerID = command.parameters["layer"] ?? page.selectedLayerID
        guard let layer = page.ensureLayer(id: layerID) else {
            return [pageLimitError(page, "layers")]
        }
        guard !layer.isReadOnly else {
            return [pageError(page.id, reason: "readOnlyLayer", ("layer", layer.id))]
        }
        // Inside the layer's own scene everything lives on its default layer;
        // `layer=` has already been spent choosing the page layer.
        var routed = command
        routed.parameters.removeValue(forKey: "layer")
        layer.scene.apply(routed)

        guard let id = command.parameters["id"],
              let primitive = layer.scene.primitive(id: id),
              let bounds = layer.scene.bounds(for: primitive) else {
            return []
        }
        return grow(page, toFit: bounds, in: layer, mode: mode)
    }

    private func movePrimitive(_ command: VectorTerminalGraphicsCommand, in page: VTGPage) -> [String] {
        guard let id = command.parameters["id"],
              let destinationID = command.parameters["layer"] ?? command.parameters["value"] else {
            return []
        }
        guard let source = page.layers.first(where: { !$0.isReadOnly && $0.scene.primitive(id: id) != nil }),
              let primitive = source.scene.primitive(id: id) else {
            return []
        }
        guard let destination = page.ensureLayer(id: destinationID) else {
            return [pageLimitError(page, "layers")]
        }
        guard !destination.isReadOnly else {
            return [pageError(page.id, reason: "readOnlyLayer", ("layer", destination.id))]
        }
        source.scene.remove(id: id)
        destination.scene.insertPrimitive(primitive)
        return []
    }

    /// Extend a growable page to fit freshly drawn content. A fixed axis
    /// clips instead; the primitive stays retained.
    private func grow(_ page: VTGPage, toFit bounds: VTGBounds, in layer: VTGPageLayer, mode: VTGPageModeState) -> [String] {
        guard layer.scrollMode == .page else {
            return []
        }
        var responses: [String] = []
        var grew = false
        let neededWidth = bounds.maxX + layer.offset.x + page.padding
        let neededHeight = bounds.maxY + layer.offset.y + page.padding
        if page.growsWidth, neededWidth > page.width {
            let newWidth = min(neededWidth, page.maxWidth)
            if newWidth > page.width {
                page.width = newWidth
                grew = true
            }
            if neededWidth > page.maxWidth {
                responses.append(contentsOf: reportLimitOnce(page, "w"))
            }
        }
        if page.growsHeight, neededHeight > page.height {
            let newHeight = min(neededHeight, page.maxHeight)
            if newHeight > page.height {
                page.height = newHeight
                grew = true
            }
            if neededHeight > page.maxHeight {
                responses.append(contentsOf: reportLimitOnce(page, "h"))
            }
        }
        if grew, !mode.grewPageIDs.contains(page.id) {
            mode.grewPageIDs.append(page.id)
        }
        return responses
    }

    private func reportLimitOnce(_ page: VTGPage, _ axis: String) -> [String] {
        guard !page.reportedLimits.contains(axis) else {
            return []
        }
        page.reportedLimits.insert(axis)
        return [pageLimitError(page, axis)]
    }

    /// Events that are coalesced to one per batch, and a resize to any
    /// subscriber when page mode changed what "the canvas" means.
    func flushPageBatchEvents(canvas: VTGCanvasSize) -> [String] {
        guard pageScopeTouched else {
            return []
        }
        pageScopeTouched = false
        var responses: [String] = []
        if let mode = activePageMode {
            for id in mode.grewPageIDs {
                guard let page = mode.page(id: id) else { continue }
                responses.append(pageEvent(
                    "pageGrew",
                    ("id", page.id),
                    ("w", Self.pageNumber(page.width)),
                    ("h", Self.pageNumber(page.height))
                ))
            }
            mode.grewPageIDs.removeAll()
        }
        if sendsResizeEvents, canvas.width > 0, canvas.height > 0 {
            let reported = reportedCanvas(for: canvas)
            if reported != lastReportedCanvas {
                lastReportedCanvas = reported
                responses.append(VTGResponseEncoder.resize(canvas: reported))
            }
        }
        return responses
    }

    // MARK: - Size scope

    /// What `canvas?`, `size?`, and `resize` report: the page viewport while a
    /// page is open, the real canvas otherwise. `windowCanvas?` always
    /// reports the real one.
    public func reportedCanvas(for canvas: VTGCanvasSize) -> VTGCanvasSize {
        guard let page = pageModeState?.sizeReportingPage else {
            return canvas
        }
        let viewport = page.viewportSize(canvas: canvas)
        return VTGCanvasSize(
            width: max(1, Int(viewport.width.rounded())),
            height: max(1, Int(viewport.height.rounded()))
        )
    }

    /// Apply each page's resize policy after the window changed size.
    public func pageWindowResizeResponses(canvas: VTGCanvasSize) -> [String] {
        guard let mode = pageModeState, canvas.width > 0, canvas.height > 0 else {
            return []
        }
        var responses: [String] = []
        for page in mode.pages {
            let oldWidth = page.width, oldHeight = page.height
            let width = Double(canvas.width), height = Double(canvas.height)
            let followsWidth: Bool
            let followsHeight: Bool
            switch page.resizePolicy {
            case .fixed:
                (followsWidth, followsHeight) = (false, false)
            case .followWidth:
                (followsWidth, followsHeight) = (true, false)
            case .followViewport:
                (followsWidth, followsHeight) = (true, true)
            case .auto:
                (followsWidth, followsHeight) = (page.widthFromWindow, page.heightFromWindow)
            }
            if followsWidth {
                page.width = page.growsWidth ? max(page.width, width) : width
            }
            if followsHeight {
                page.height = page.growsHeight ? max(page.height, height) : height
            }
            page.clampScroll(canvas: canvas)
            if page.width != oldWidth || page.height != oldHeight {
                responses.append(pageResizedEvent(page, reason: "window"))
            }
        }
        return responses
    }

    // MARK: - Input

    /// Map a canvas point into the visible page, if it lands inside it.
    public func pagePoint(for point: VTGPoint, canvas: VTGCanvasSize) -> (page: VTGPage, x: Double, y: Double)? {
        guard graphicsLayersVisible, let page = pageModeState?.visiblePage else {
            return nil
        }
        let origin = page.viewport.map { VTGPoint(x: $0.x, y: $0.y) } ?? VTGPoint(x: 0, y: 0)
        let size = page.viewportSize(canvas: canvas)
        let localX = point.x - origin.x
        let localY = point.y - origin.y
        guard localX >= 0, localY >= 0, localX < size.width, localY < size.height else {
            return nil
        }
        return (page, localX + page.scrollX, localY + page.scrollY)
    }

    /// The topmost page hit region under a canvas point.
    func pageHit(at point: VTGPoint, canvas: VTGCanvasSize) -> (layer: VTGPageLayer, region: VTGHitRegion)? {
        guard let mapped = pagePoint(for: point, canvas: canvas) else {
            return nil
        }
        for layer in mapped.page.orderedLayers.reversed() where layer.isVisible {
            let base = layer.scrollMode == .page
                ? VTGPoint(x: mapped.x, y: mapped.y)
                : VTGPoint(x: mapped.x - mapped.page.scrollX, y: mapped.y - mapped.page.scrollY)
            let local = VTGPoint(x: base.x - layer.offset.x, y: base.y - layer.offset.y)
            if let region = layer.scene.hitRegion(at: local) {
                return (layer, region)
            }
        }
        return nil
    }

    /// Scroll the visible page from a user wheel or trackpad gesture.
    ///
    /// Returns `nil` when page mode does not want the gesture, which leaves
    /// it to reach the program as an ordinary scroll event.
    public func pageUserScrollResponse(
        at point: VTGPoint,
        deltaX: Double,
        deltaY: Double,
        canvas: VTGCanvasSize
    ) -> [String]? {
        guard let mode = pageModeState, mode.userScrollEnabled,
              let mapped = pagePoint(for: point, canvas: canvas) else {
            return nil
        }
        let page = mapped.page
        let oldX = page.scrollX, oldY = page.scrollY
        if mode.userScrollAxis != .y {
            page.scrollX -= deltaX
        }
        if mode.userScrollAxis != .x {
            page.scrollY -= deltaY
        }
        page.clampScroll(canvas: canvas)
        guard page.scrollX != oldX || page.scrollY != oldY else {
            return []
        }
        return [pageEvent(
            "pageScrolled",
            ("id", page.id),
            ("x", Self.pageNumber(page.scrollX)),
            ("y", Self.pageNumber(page.scrollY)),
            ("source", "user")
        )]
    }

    // MARK: - Queries

    private func pageQueryResponse() -> String {
        guard let mode = pageModeState else {
            return pageEvent("page", ("active", "0"))
        }
        let target = mode.drawsToBase ? "base" : (mode.targetPage?.id ?? "none")
        return pageEvent(
            "page",
            ("active", "1"),
            ("session", mode.sessionID),
            ("target", target),
            ("visible", mode.visiblePage?.id ?? "none")
        )
    }

    private func pageStateResponse(_ page: VTGPage, mode: VTGPageModeState) -> String {
        pageEvent(
            "pageState",
            ("id", page.id),
            ("slot", page.slot.rawValue),
            ("w", Self.pageNumber(page.width)),
            ("h", Self.pageNumber(page.height)),
            ("growW", page.growsWidth ? "1" : "0"),
            ("growH", page.growsHeight ? "1" : "0"),
            ("scrollX", Self.pageNumber(page.scrollX)),
            ("scrollY", Self.pageNumber(page.scrollY)),
            ("alpha", Self.pageNumber(page.alpha)),
            ("bg", page.background.map(Self.hexColor) ?? "none"),
            ("visible", mode.visibleSlot == page.slot ? "1" : "0"),
            ("layers", page.orderedLayers.map(\.id).joined(separator: "|"))
        )
    }

    private func pageLimitsResponse(_ page: VTGPage?, canvas: VTGCanvasSize) -> String {
        pageEvent(
            "pageLimits",
            ("maxPages", "2"),
            ("maxLayers", String(VTGPage.maximumLayers)),
            ("maxW", Self.pageNumber(page?.maxWidth ?? Double(canvas.width) * 16)),
            ("maxH", Self.pageNumber(page?.maxHeight ?? Double(canvas.height) * 16)),
            ("maxStyles", String(VTGTextStyleRegistry.maximumStyles)),
            ("maxCacheLayers", String(VTGPageCacheLimits.maximumLayers)),
            ("maxCacheArea", Self.pageNumber(VTGPageCacheLimits.maximumArea))
        )
    }

    private func textMeasureResponse(_ command: VectorTerminalGraphicsCommand) -> String {
        let queryID = command.parameters["id"] ?? "measure"
        guard let text = scene.parseRichText(command) else {
            return pageEvent("textMeasure", ("id", queryID), ("error", "badParam"))
        }
        let metrics = VTGTextLayout.metrics(for: text)
        return pageEvent(
            "textMeasure",
            ("id", queryID),
            ("w", Self.pageNumber(metrics.width)),
            ("h", Self.pageNumber(metrics.height)),
            ("lines", String(metrics.lineCount)),
            ("firstBaseline", Self.pageNumber(metrics.firstBaseline)),
            ("lastBaseline", Self.pageNumber(metrics.lastBaseline)),
            ("truncated", metrics.truncated ? "1" : "0"),
            ("fontResolved", metrics.resolvedFonts.map(Self.fieldSafe).joined(separator: "|"))
        )
    }

    private func fontsResponse() -> String {
        let families = VTGFontCatalog.availableFamilies.map(Self.fieldSafe)
        let defaultFamily = Self.fieldSafe(VTGFontCatalog.defaultFamily)
        return pageEvent(
            "fonts",
            ("default", defaultFamily),
            ("generic", "sans|serif|mono|terminal"),
            ("count", String(families.count)),
            ("families", families.joined(separator: "|"))
        )
    }

    // MARK: - Encoding helpers

    private func namedPage(
        _ command: VectorTerminalGraphicsCommand,
        mode: VTGPageModeState,
        key: String = "id",
        required: Bool = false
    ) -> VTGPage? {
        if let id = command.parameters[key] {
            return mode.page(id: id)
        }
        return required ? nil : mode.targetPage
    }

    private func pageEvent(_ name: String, _ fields: (String, String)...) -> String {
        VTGResponseEncoder.apc(name, fields)
    }

    private func pageRejected(_ command: VectorTerminalGraphicsCommand, reason: String) -> String {
        pageEvent(
            "pageRejected",
            ("id", command.parameters["id"] ?? pageModeState?.sessionID ?? "none"),
            ("command", command.name),
            ("reason", reason)
        )
    }

    private func pageError(_ id: String, reason: String, _ extra: (String, String)...) -> String {
        VTGResponseEncoder.apc("pageError", [("id", id), ("reason", reason)] + extra)
    }

    private func pageLimitError(_ page: VTGPage, _ what: String) -> String {
        pageError(page.id, reason: "limit", ("limit", what))
    }

    private func pageResizedEvent(_ page: VTGPage, reason: String) -> String {
        pageEvent(
            "pageResized",
            ("id", page.id),
            ("w", Self.pageNumber(page.width)),
            ("h", Self.pageNumber(page.height)),
            ("reason", reason)
        )
    }

    static func pageNumber(_ value: Double) -> String {
        guard value.isFinite else {
            return "0"
        }
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded(), abs(rounded) < 1e15 {
            return String(Int(rounded))
        }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }

    static func hexColor(_ color: VTGColor) -> String {
        func channel(_ value: Double) -> String {
            String(format: "%02x", Int((min(1, max(0, value)) * 255).rounded()))
        }
        return "#\(channel(color.red))\(channel(color.green))\(channel(color.blue))\(channel(color.alpha))"
    }

    /// Keep a free-form name from ending a header field or splitting a list.
    static func fieldSafe(_ value: String) -> String {
        value.replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: ";", with: " ")
            .replacingOccurrences(of: "=", with: " ")
    }

    static func isTruthy(_ value: String?) -> Bool {
        switch value?.lowercased() {
        case "1", "true", "yes", "on": return true
        default: return false
        }
    }
}

extension VTGGraphicsScene {
    /// The retained primitive with this id, if any.
    func primitive(id: String) -> VTGPrimitive? {
        indexesByID[id].map { primitives[$0] }
    }

    /// Insert or replace a primitive on the scene's default layer.
    func insertPrimitive(_ primitive: VTGPrimitive) {
        upsert(primitive, command: VectorTerminalGraphicsCommand(name: "layer"))
    }
}
