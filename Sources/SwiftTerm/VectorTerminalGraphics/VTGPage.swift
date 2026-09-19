import Foundation

// VTG Page Mode (VPM): an off-screen page — a document with its own size,
// background, layer stack, and scroll position — that floats above the
// ordinary terminal view. See PAGE_MODE.md for the protocol.

/// The two page buffers. A page opened while another is visible always lands
/// in the other one.
public enum VTGPageSlot: String, CaseIterable {
    case a = "A"
    case b = "B"

    var index: Int { self == .a ? 0 : 1 }

    init(index: Int) {
        self = index == 0 ? .a : .b
    }
}

/// Where the visible page composites relative to the existing overlays.
public enum VTGPageStacking: String {
    /// Above everything, including VTG overlay layers 1–4.
    case all
    /// Above terminal text, beneath VTG overlay layers.
    case text
}

/// What a page does when the terminal window changes size.
public enum VTGPageResizePolicy: String {
    /// Axes whose size came from the window follow it; explicit sizes stay.
    case auto
    case fixed
    case followWidth
    case followViewport
}

/// Whether a page layer moves with the page's scroll offset.
public enum VTGPageLayerScrollMode: String {
    case page
    /// Pinned to the viewport, like a HUD over a scrolling document.
    case fixed
}

/// Which axes the user's wheel or trackpad scrolls.
public enum VTGPageScrollAxis: String {
    case both
    case x
    case y
}

/// One named layer of a page.
///
/// The content is an ordinary retained ``VTGGraphicsScene``, so every VTG
/// primitive works in a page unchanged. A layer borrowed from another page with
/// `pageLayerCopy,mode=reference` shares that page's scene instance and is
/// read-only here.
public final class VTGPageLayer {
    public let id: String
    public internal(set) var z: Double
    /// Creation order, which breaks z ties.
    let order: Int
    public internal(set) var alpha: Double = 1
    public internal(set) var isVisible = true
    public internal(set) var offset = VTGLayerOffset.zero
    public internal(set) var scrollMode: VTGPageLayerScrollMode = .page
    /// Renderer hint: the layer changes rarely and may be rasterized once.
    public internal(set) var cacheHint = false
    public internal(set) var scene: VTGGraphicsScene
    /// The page this layer is borrowed from, when it is a reference.
    public internal(set) var sourcePageID: String?
    public internal(set) var sourceLayerID: String?

    /// Borrowed layers are drawn into through their owner, never here.
    public var isReadOnly: Bool { sourcePageID != nil }

    init(id: String, z: Double, order: Int, scene: VTGGraphicsScene) {
        self.id = id
        self.z = z
        self.order = order
        self.scene = scene
    }
}

/// What a renderer will keep rasterized for `cache=1` and borrowed layers.
///
/// Lives here, rather than in the view, so `pageLimits?` can report the same
/// numbers the compositor actually applies.
public enum VTGPageCacheLimits {
    /// Rasters kept at once, across both pages. Least recently drawn go first.
    public static let maximumLayers = 8
    /// Pages larger than this are drawn directly rather than rasterized.
    public static let maximumArea = 4096.0 * 4096.0
}

/// A page buffer.
public final class VTGPage {
    public static let maximumLayers = 32
    public static let defaultLayerID = "1"

    public let id: String
    public let slot: VTGPageSlot
    /// Current extent in page space.
    public internal(set) var width: Double
    public internal(set) var height: Double
    public internal(set) var growsWidth: Bool
    public internal(set) var growsHeight: Bool
    public internal(set) var maxWidth: Double
    public internal(set) var maxHeight: Double
    public internal(set) var padding: Double
    /// `nil` is transparent: the terminal shows through.
    public internal(set) var background: VTGColor?
    public internal(set) var alpha: Double = 1
    /// Where the page's visible window sits on the canvas. `nil` is the
    /// whole canvas.
    public internal(set) var viewport: VTGLayerClip?
    public internal(set) var scrollX: Double = 0
    public internal(set) var scrollY: Double = 0
    public internal(set) var resizePolicy: VTGPageResizePolicy
    /// Whether each axis's size was taken from the window rather than given.
    var widthFromWindow: Bool
    var heightFromWindow: Bool
    public internal(set) var layers: [VTGPageLayer] = []
    /// Layer that drawing without `layer=` goes to.
    public internal(set) var selectedLayerID = VTGPage.defaultLayerID
    /// Session style registry, shared with the base scene.
    let textStyles: VTGTextStyleRegistry
    /// Holds uploaded sprite assets for every layer of this page.
    let assets = VTGGraphicsScene()
    var nextLayerOrder = 0
    /// Limits already reported, so a runaway loop reports each once.
    var reportedLimits: Set<String> = []

    init(
        id: String,
        slot: VTGPageSlot,
        width: Double,
        height: Double,
        growsWidth: Bool,
        growsHeight: Bool,
        maxWidth: Double,
        maxHeight: Double,
        padding: Double,
        background: VTGColor?,
        resizePolicy: VTGPageResizePolicy,
        widthFromWindow: Bool,
        heightFromWindow: Bool,
        textStyles: VTGTextStyleRegistry
    ) {
        self.id = id
        self.slot = slot
        self.width = width
        self.height = height
        self.growsWidth = growsWidth
        self.growsHeight = growsHeight
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.padding = padding
        self.background = background
        self.resizePolicy = resizePolicy
        self.widthFromWindow = widthFromWindow
        self.heightFromWindow = heightFromWindow
        self.textStyles = textStyles
        assets.textStyles = textStyles
    }

    /// Layers in drawing order: by `z`, then by creation.
    public var orderedLayers: [VTGPageLayer] {
        layers.sorted { lhs, rhs in
            lhs.z == rhs.z ? lhs.order < rhs.order : lhs.z < rhs.z
        }
    }

    public func layer(id: String) -> VTGPageLayer? {
        layers.first { $0.id == id }
    }

    /// Return the named layer, creating it when absent. A numeric id is
    /// created at that z, which is what lets `layer=<n>` from existing VTG code
    /// land in a page unmodified. `nil` when the layer limit is reached.
    @discardableResult
    func ensureLayer(id: String, z: Double? = nil) -> VTGPageLayer? {
        if let existing = layer(id: id) {
            return existing
        }
        guard layers.count < Self.maximumLayers else {
            return nil
        }
        let scene = VTGGraphicsScene()
        scene.textStyles = textStyles
        syncAssets(into: scene)
        let layer = VTGPageLayer(
            id: id,
            z: z ?? Double(id) ?? Double(nextLayerOrder),
            order: nextLayerOrder,
            scene: scene
        )
        nextLayerOrder += 1
        layers.append(layer)
        return layer
    }

    /// Insert an existing layer object (a copy or a reference).
    func insert(_ layer: VTGPageLayer) -> Bool {
        if let index = layers.firstIndex(where: { $0.id == layer.id }) {
            layers[index] = layer
            return true
        }
        guard layers.count < Self.maximumLayers else {
            return false
        }
        layers.append(layer)
        nextLayerOrder = max(nextLayerOrder, layer.order + 1)
        return true
    }

    func removeLayer(id: String) {
        layers.removeAll { $0.id == id }
    }

    /// Copy uploaded sprite assets into a layer scene. Dictionaries of value
    /// types, so the image bytes are shared, not duplicated.
    func syncAssets(into scene: VTGGraphicsScene) {
        scene.spriteAssets = assets.spriteAssets
        scene.vectorSpriteAssets = assets.vectorSpriteAssets
        scene.indexedSpriteAssets = assets.indexedSpriteAssets
    }

    func syncAssetsIntoOwnLayers() {
        for layer in layers where !layer.isReadOnly {
            syncAssets(into: layer.scene)
        }
    }

    /// A copy of this page for an offscreen frame to draw into.
    ///
    /// Layers the page owns are copied, so drawing during the frame cannot be
    /// seen until it commits. Layers borrowed from the other page keep
    /// pointing at that page's scene: they are read-only here, and their
    /// owner's changes are not part of this frame.
    func copyForFrame() -> VTGPage {
        let copy = VTGPage(
            id: id,
            slot: slot,
            width: width,
            height: height,
            growsWidth: growsWidth,
            growsHeight: growsHeight,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            padding: padding,
            background: background,
            resizePolicy: resizePolicy,
            widthFromWindow: widthFromWindow,
            heightFromWindow: heightFromWindow,
            textStyles: textStyles
        )
        copy.alpha = alpha
        copy.viewport = viewport
        copy.scrollX = scrollX
        copy.scrollY = scrollY
        copy.selectedLayerID = selectedLayerID
        copy.nextLayerOrder = nextLayerOrder
        copy.reportedLimits = reportedLimits
        copy.assets.replaceContents(with: assets)
        copy.layers = layers.map { layer in
            let copied = VTGPageLayer(
                id: layer.id,
                z: layer.z,
                order: layer.order,
                scene: layer.isReadOnly ? layer.scene : layer.scene.makeSnapshot()
            )
            copied.alpha = layer.alpha
            copied.isVisible = layer.isVisible
            copied.offset = layer.offset
            copied.scrollMode = layer.scrollMode
            copied.cacheHint = layer.cacheHint
            copied.sourcePageID = layer.sourcePageID
            copied.sourceLayerID = layer.sourceLayerID
            return copied
        }
        return copy
    }

    /// Size of the visible window onto the page, in canvas pixels.
    func viewportSize(canvas: VTGCanvasSize) -> (width: Double, height: Double) {
        if let viewport {
            return (viewport.width, viewport.height)
        }
        return (Double(canvas.width), Double(canvas.height))
    }

    /// Set the scroll origin without clamping, for tests and for hosts that
    /// clamp themselves.
    func scrollTo(x: Double, y: Double) {
        scrollX = x
        scrollY = y
    }

    /// Keep the scroll origin inside the page.
    func clampScroll(canvas: VTGCanvasSize) {
        let view = viewportSize(canvas: canvas)
        scrollX = min(max(0, scrollX), max(0, width - view.width))
        scrollY = min(max(0, scrollY), max(0, height - view.height))
    }
}

/// Everything page mode knows between `pageBegin` and `pageEnd`.
public final class VTGPageModeState {
    public let sessionID: String
    public internal(set) var stacking: VTGPageStacking
    var slots: [VTGPage?] = [nil, nil]
    public internal(set) var visibleSlot: VTGPageSlot?
    public internal(set) var targetSlot: VTGPageSlot?
    /// `pageTarget,scene=base`: drawing goes to the ordinary scene while page
    /// mode stays active.
    public internal(set) var drawsToBase = false
    public internal(set) var userScrollEnabled = false
    public internal(set) var userScrollAxis: VTGPageScrollAxis = .both
    /// Pages whose extent grew during the current command batch.
    var grewPageIDs: [String] = []

    init(sessionID: String, stacking: VTGPageStacking) {
        self.sessionID = sessionID
        self.stacking = stacking
    }

    public var pages: [VTGPage] {
        slots.compactMap { $0 }
    }

    public func page(in slot: VTGPageSlot) -> VTGPage? {
        slots[slot.index]
    }

    public func page(id: String) -> VTGPage? {
        pages.first { $0.id == id }
    }

    public var visiblePage: VTGPage? {
        visibleSlot.flatMap(page(in:))
    }

    public var targetPage: VTGPage? {
        targetSlot.flatMap(page(in:))
    }

    /// A copy of the whole of page mode for an offscreen frame to work in.
    ///
    /// A frame covers what the program draws, and in page mode that is not
    /// only the drawing: a frame may open a page, draw it, and show it. All
    /// of that lands at once when the frame commits, so copying one page is
    /// not enough — the copy is of both buffers and which is on screen.
    func copyForFrame() -> VTGPageModeState {
        let copy = VTGPageModeState(sessionID: sessionID, stacking: stacking)
        copy.slots = slots.map { $0?.copyForFrame() }
        copy.visibleSlot = visibleSlot
        copy.targetSlot = targetSlot
        copy.drawsToBase = drawsToBase
        copy.userScrollEnabled = userScrollEnabled
        copy.userScrollAxis = userScrollAxis
        return copy
    }

    /// The page whose viewport stands in for the canvas in size queries.
    var sizeReportingPage: VTGPage? {
        visiblePage ?? targetPage
    }
}
