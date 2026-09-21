import UIKit

/// A sprite made on the device, to check sprites draw on iOS (IPAD_PLAN 2.6).
///
/// The sprite path is the one AppKit call that became a UIKit call rather than
/// an alias: `VTGPlatformImage(data:)` and `draw(in:)` inside a context the
/// sprite transform has rotated. So this uploads a PNG and places it three
/// times — plain, rotated, and scaled with nearest-neighbour filtering — which
/// exercises exactly that.
enum HarnessSprite {
    static var scene: String {
        guard let png = makePNG() else {
            return ""
        }
        let base64 = png.base64EncodedString()
        return HarnessScenes.vtg("spriteUpload,id=ship,format=png,width=16,height=16,filter=nearest;\(base64)")
            + HarnessScenes.vtg("sprite,id=s1,image=ship,x=640,y=240,rotation=0,scale=3")
            + HarnessScenes.vtg("sprite,id=s2,image=ship,x=640,y=330,rotation=45,scale=3")
            + HarnessScenes.vtg("sprite,id=s3,image=ship,x=640,y=420,rotation=0,scale=5")
    }

    /// A 16x16 pixel-art ship, drawn with UIKit and encoded as PNG.
    private static func makePNG() -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(red: 0.37, green: 0.92, blue: 0.83, alpha: 1).cgColor)
            cg.fill(CGRect(x: 7, y: 1, width: 2, height: 10))
            cg.fill(CGRect(x: 4, y: 6, width: 8, height: 4))
            cg.fill(CGRect(x: 1, y: 9, width: 14, height: 3))
            cg.setFillColor(UIColor(red: 0.98, green: 0.57, blue: 0.24, alpha: 1).cgColor)
            cg.fill(CGRect(x: 5, y: 12, width: 2, height: 3))
            cg.fill(CGRect(x: 9, y: 12, width: 2, height: 3))
        }
        return image.pngData()
    }
}
