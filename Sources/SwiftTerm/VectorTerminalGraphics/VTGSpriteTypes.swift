import Foundation

/// Uploaded bitmap payload that sprite instances can reference cheaply.
public struct VTGSpriteAsset: Equatable {
    public var id: String
    public var format: String
    public var width: Double
    public var height: Double
    public var data: Data
    public var base64: String

    public init(id: String, format: String, width: Double, height: Double, data: Data, base64: String) {
        self.id = id
        self.format = format
        self.width = width
        self.height = height
        self.data = data
        self.base64 = base64
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
