import Foundation

/// Host-side link detection settings controlled by the VTG protocol.
public struct VTGLinkDetectionSettings: Equatable {
    /// Whether explicit and implicit links can be hovered or activated.
    public var isEnabled: Bool

    /// Whether detected links receive link-colored text and an underline.
    public var decoratesLinks: Bool

    /// Link decoration color.
    public var color: VTGColor

    /// Create link detection settings.
    public init(
        isEnabled: Bool = true,
        decoratesLinks: Bool = true,
        color: VTGColor = VTGColor(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    ) {
        self.isEnabled = isEnabled
        self.decoratesLinks = decoratesLinks
        self.color = color
    }
}
