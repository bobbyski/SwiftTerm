import Foundation

/// What may hide a VTG graphics layer.
///
/// ```text
///   none (default)              ink
///   ─────────────────────       ──────────────────────────────────────
///   ┌────────────┐              ┌────────────┐
///   │  ●●●●●●    │              │  ●●●┌──────────┐
///   │ ●●●●●●●●┌──────────┐      │ ●●●●│ Menu     │   cells with ink cut
///   │ ●●●●●●●●│●Menu●●●  │      │ ●●●●│ Open     │   holes in the layer
///   │  ●●●●●●●│●Open●●   │      │  ●●●└──────────┘
///   └─────────└──────────┘      └────────────┘
///   graphics float over text    text in front of graphics
/// ```
///
/// Every layer starts at `.none`, which is how VTG has always drawn: graphics
/// above text. A program asks for `.ink` per layer with
/// `layerOcclude,layer=<n>,by=ink`. The layer then keeps its place in the
/// stack; it simply is not drawn inside any cell that holds ink — a visible
/// character, a non-default background, or a decoration (see `VTGCellInkRule`).
public enum VTGLayerOcclusion: String, Equatable {
    /// Nothing hides the layer. The default, and VTG's original behavior.
    case none
    /// Terminal cells with ink hide the layer, cell by cell.
    case ink
}

/// A set of rectangles, in VTG canvas points, that a masked layer is not drawn
/// inside.
///
/// The rectangles never overlap: the builder merges each row's cells into runs,
/// and rows do not overlap each other. Renderers rely on that — an even-odd
/// clip, for one, would turn an overlap back into a visible region.
public struct VTGOcclusionMask: Equatable {
    /// The holes, in canvas points.
    public var rects: [VTGLayerClip]

    /// A mask with no holes: the layer draws exactly as it would unmasked.
    public static let empty = VTGOcclusionMask(rects: [])

    /// Whether the mask hides nothing.
    public var isEmpty: Bool {
        rects.isEmpty
    }

    /// Create a mask from disjoint rectangles.
    public init(rects: [VTGLayerClip]) {
        self.rects = rects
    }
}

extension VTGOcclusionMask {
    /// The part of a canvas the mask leaves visible, as disjoint rectangles.
    ///
    /// ```text
    ///   ┌──────────────────────┐        ┌──────────────────────┐ a
    ///   │                      │        ├────┐ hole ┌──────────┤ b c
    ///   │    ┌──────┐          │   →    │    │      │          │
    ///   │    └──────┘          │        ├────┴──────┴──────────┤ d
    ///   └──────────────────────┘        └──────────────────────┘
    /// ```
    ///
    /// For renderers that cannot subtract a shape and can only draw inside
    /// rectangles (the Metal primitive path clips triangles to these). Bands
    /// with the same spans are merged, so a screen of text yields roughly one
    /// rectangle per gap rather than one per cell.
    public func visibleRects(width: Double, height: Double) -> [VTGLayerClip] {
        guard width > 0, height > 0 else {
            return []
        }
        guard !rects.isEmpty else {
            return [VTGLayerClip(x: 0, y: 0, width: width, height: height)]
        }
        var edges = Set<Double>([0, height])
        for hole in rects {
            edges.insert(min(height, max(0, hole.y)))
            edges.insert(min(height, max(0, hole.y + hole.height)))
        }
        let bands = edges.sorted()
        var result: [VTGLayerClip] = []
        // Rectangles still open from the band above, by their x span.
        var open: [Range<Double>: Int] = [:]
        for index in 0..<(bands.count - 1) {
            let top = bands[index]
            let bottom = bands[index + 1]
            guard bottom > top else { continue }
            let covering = rects
                .filter { $0.y <= top && $0.y + $0.height >= bottom }
                .map { max(0, $0.x)..<min(width, $0.x + $0.width) }
                .filter { !$0.isEmpty }
                .sorted { $0.lowerBound < $1.lowerBound }
            var spans: [Range<Double>] = []
            var cursor = 0.0
            for hole in covering {
                if hole.lowerBound > cursor {
                    spans.append(cursor..<hole.lowerBound)
                }
                cursor = max(cursor, hole.upperBound)
            }
            if cursor < width {
                spans.append(cursor..<width)
            }
            var nextOpen: [Range<Double>: Int] = [:]
            for span in spans {
                if let existing = open[span], result[existing].y + result[existing].height == top {
                    result[existing].height = bottom - result[existing].y
                    nextOpen[span] = existing
                } else {
                    result.append(VTGLayerClip(x: span.lowerBound, y: top,
                                               width: span.upperBound - span.lowerBound, height: bottom - top))
                    nextOpen[span] = result.count - 1
                }
            }
            open = nextOpen
        }
        return result
    }
}

extension VTGGraphicsScene {
    /// `layerOcclude,layer=<n>,by=none|ink`
    ///
    /// Unknown `by=` values are treated as `none`, so a typo never hides
    /// graphics the program meant to show.
    func setLayerOcclusion(_ command: VectorTerminalGraphicsCommand) {
        let layer = command.layerValue(default: defaultLayer)
        guard VTGLayerModel.supportedRange.contains(layer) else {
            return
        }
        let occlusion = VTGLayerOcclusion(rawValue: command.parameters["by"] ?? "none") ?? .none
        if occlusion == .none {
            layerOcclusions.removeValue(forKey: layer)
        } else {
            layerOcclusions[layer] = occlusion
        }
    }

    /// What may hide the given layer.
    public func occlusion(for layer: Int) -> VTGLayerOcclusion {
        layerOcclusions[layer] ?? .none
    }

    /// Whether any layer has asked to be hidden by text, so a renderer can skip
    /// building a mask for the common case where none has.
    public var usesTextOcclusion: Bool {
        layerOcclusions.values.contains(.ink)
    }
}
