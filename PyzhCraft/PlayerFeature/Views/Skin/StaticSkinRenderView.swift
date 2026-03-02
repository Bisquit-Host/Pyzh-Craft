import SwiftUI
import SceneKit
import SkinRenderKit

/// Static skin renderer that keeps rotation behavior but disables walking animation
struct StaticSkinRenderView: NSViewControllerRepresentable {
    let texturePath: String?
    let skinImage: NSImage?
    @Binding var capeImage: NSImage?
    let playerModel: PlayerModel
    let rotationDuration: TimeInterval
    let backgroundColor: NSColor
    
    init(
        texturePath: String? = nil,
        capeImage: Binding<NSImage?>,
        playerModel: PlayerModel = .steve,
        rotationDuration: TimeInterval = 0,
        backgroundColor: NSColor = .clear
    ) {
        self.texturePath = texturePath
        self.skinImage = nil
        self._capeImage = capeImage
        self.playerModel = playerModel
        self.rotationDuration = rotationDuration
        self.backgroundColor = backgroundColor
    }
    
    init(
        skinImage: NSImage,
        capeImage: Binding<NSImage?>,
        playerModel: PlayerModel = .steve,
        rotationDuration: TimeInterval = 0,
        backgroundColor: NSColor = .clear
    ) {
        self.texturePath = nil
        self.skinImage = skinImage
        self._capeImage = capeImage
        self.playerModel = playerModel
        self.rotationDuration = rotationDuration
        self.backgroundColor = backgroundColor
    }
    
    func makeNSViewController(context: Context) -> SceneKitCharacterViewController {
        let controller: SceneKitCharacterViewController
        
        if let skinImage {
            controller = SceneKitCharacterViewController(
                skinImage: skinImage,
                capeImage: capeImage,
                playerModel: playerModel,
                rotationDuration: rotationDuration,
                backgroundColor: backgroundColor
            )
        } else if let texturePath {
            controller = SceneKitCharacterViewController(
                texturePath: texturePath,
                capeTexturePath: nil,
                playerModel: playerModel,
                rotationDuration: rotationDuration,
                backgroundColor: backgroundColor
            )
        } else {
            controller = SceneKitCharacterViewController(
                playerModel: playerModel,
                rotationDuration: rotationDuration,
                backgroundColor: backgroundColor
            )
        }
        
        return controller
    }
    
    func updateNSViewController(_ nsViewController: SceneKitCharacterViewController, context: Context) {
        nsViewController.updatePlayerModel(playerModel)
        
        if let skinImage {
            nsViewController.updateTexture(image: skinImage)
        } else if let texturePath {
            nsViewController.updateTexture(path: texturePath)
        } else {
            nsViewController.loadDefaultTexture()
        }
        
        if let capeImage {
            nsViewController.updateCapeTexture(image: capeImage)
        } else {
            nsViewController.removeCapeTexture()
        }
        
        nsViewController.updateRotationDuration(rotationDuration)
        nsViewController.updateBackgroundColor(backgroundColor)
        disableWalkingIfNeeded(for: nsViewController)
    }
    
    private func disableWalkingIfNeeded(for controller: SceneKitCharacterViewController) {
        guard hasWalkingAnimation(in: controller.view) else {
            return
        }
        
        let selector = NSSelectorFromString("toggleWalkingAnimationAction")
        guard controller.responds(to: selector) else {
            return
        }
        
        controller.perform(selector)
    }
    
    private func hasWalkingAnimation(in view: NSView) -> Bool {
        if let scnView = view as? SCNView, hasWalkingAnimation(in: scnView.scene?.rootNode) {
            return true
        }
        
        for subview in view.subviews where hasWalkingAnimation(in: subview) {
            return true
        }
        
        return false
    }
    
    private func hasWalkingAnimation(in node: SCNNode?) -> Bool {
        guard let node else { return false }
        
        if node.action(forKey: "walkSwing") != nil || node.action(forKey: "headBob") != nil {
            return true
        }
        
        for child in node.childNodes where hasWalkingAnimation(in: child) {
            return true
        }
        
        return false
    }
}
