import Foundation

/// Sampling hint for raster sprite assets.
///
/// The terminal may map these to renderer-specific interpolation settings.
/// `smooth` preserves the historical behavior for image-like sprites, while
/// `nearest` is intended for pixel-art and retro numeric sprites.
public enum VTGSpriteFilter: String, Equatable {
    case smooth
    case nearest
}

/// Uploaded bitmap payload that sprite instances can reference cheaply.
public struct VTGSpriteAsset: Equatable {
    public var id: String
    public var format: String
    public var width: Double
    public var height: Double
    public var data: Data
    public var base64: String
    public var filter: VTGSpriteFilter

    public init(id: String, format: String, width: Double, height: Double, data: Data, base64: String, filter: VTGSpriteFilter = .smooth) {
        self.id = id
        self.format = format
        self.width = width
        self.height = height
        self.data = data
        self.base64 = base64
        self.filter = filter
    }
}

/// Uploaded vector payload that sprite instances can reference cheaply.
///
/// The first pass supports one constrained VTG path per asset. That keeps
/// transforms limited to tracked sprite resources while giving small games and
/// demos lightweight vector ships, cursors, and icons.
public struct VTGVectorSpriteAsset: Equatable {
    public var id: String
    public var width: Double
    public var height: Double
    public var commands: [VTGPathCommand]
    public var stroke: VTGColor?
    public var fill: VTGColor?
    public var lineWidth: Double
    public var payload: String

    public init(id: String, width: Double, height: Double, commands: [VTGPathCommand], stroke: VTGColor?, fill: VTGColor?, lineWidth: Double, payload: String) {
        self.id = id
        self.width = width
        self.height = height
        self.commands = commands
        self.stroke = stroke
        self.fill = fill
        self.lineWidth = lineWidth
        self.payload = payload
    }
}

/// Uploaded palette-indexed sprite payload for retro BASIC-style clients.
///
/// Each value in `pixels` is an index into `palette`. `transparentIndex`, when
/// present, marks values that should not draw. This keeps small sprites easy to
/// describe with DATA arrays while still using the retained sprite transform
/// commands shared by bitmap and vector assets.
public struct VTGIndexedSpriteAsset: Equatable {
    public var id: String
    public var width: Int
    public var height: Int
    public var palette: [VTGColor]
    public var pixels: [Int]
    public var transparentIndex: Int?
    public var payload: String
    public var filter: VTGSpriteFilter

    public init(id: String, width: Int, height: Int, palette: [VTGColor], pixels: [Int], transparentIndex: Int?, payload: String, filter: VTGSpriteFilter = .nearest) {
        self.id = id
        self.width = width
        self.height = height
        self.palette = palette
        self.pixels = pixels
        self.transparentIndex = transparentIndex
        self.payload = payload
        self.filter = filter
    }
}
