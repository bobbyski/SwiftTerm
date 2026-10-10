import Foundation

/// `commandRejected`: telling a program that asked (`errorEvents`) which of
/// its sprite commands were refused, and why. Without it a refused picture
/// simply never appeared.
extension VTGHostController {
    /// Every scene a sprite command can land in: the main scene, a pending
    /// frame's copy of it, and each page's asset store and own layers.
    private var scenesTakingCommands: [VTGGraphicsScene] {
        var scenes = [scene]
        if let frameScene = pendingFrame?.scene {
            scenes.append(frameScene)
        }
        for state in [pageModeState, framePageModeState].compactMap({ $0 }) {
            for page in state.pages {
                scenes.append(page.assets)
                scenes += page.layers.filter { !$0.isReadOnly }.map(\.scene)
            }
        }
        return scenes
    }

    /// The replies for sprite commands refused since the last call, when the
    /// program asked for them. The record is emptied either way, so turning
    /// the replies on later never brings up old refusals.
    func takeRejections() -> [String] {
        var responses: [String] = []
        var seen = Set<ObjectIdentifier>()
        for scene in scenesTakingCommands where seen.insert(ObjectIdentifier(scene)).inserted {
            if sendsErrorEvents {
                responses += scene.refusals.map { refusal in
                    VTGResponseEncoder.apc("commandRejected", [
                        ("command", refusal.command),
                        ("id", refusal.id),
                        ("reason", refusal.reason),
                    ])
                }
            }
            scene.refusals.removeAll()
        }
        return responses
    }
}
