//
//  HighlightsParticleField.swift
//  Capper
//

import SpriteKit
import SwiftUI

struct HighlightsParticleField: View {
    let palette: BlogHighlightsResolvedPalette
    let burstToken: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = HighlightsParticleScene(size: UIScreen.main.bounds.size)

    var body: some View {
        GeometryReader { geo in
            if !reduceMotion {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .allowsHitTesting(false)
                    .onAppear {
                        scene.size = geo.size
                        scene.configureAmbient(color: palette.uiTint)
                    }
                    .onChange(of: geo.size) { _, size in
                        scene.size = size
                        scene.configureAmbient(color: palette.uiTint)
                    }
                    .onChange(of: paletteVersionKey) { _, _ in
                        scene.configureAmbient(color: palette.uiTint)
                    }
                    .onChange(of: burstToken) { _, token in
                        guard token > 0 else { return }
                        scene.confettiBurst(color: palette.uiTint)
                    }
            }
        }
    }

    private var paletteVersionKey: String {
        "\(palette.uiTint.description)-\(burstToken)"
    }
}

private final class HighlightsParticleScene: SKScene {
    private var ambient: SKEmitterNode?
    private lazy var dotTexture = Self.makeDotTexture()

    override init(size: CGSize) {
        super.init(size: size)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        scaleMode = .resizeFill
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    func configureAmbient(color: UIColor) {
        if ambient == nil {
            let emitter = SKEmitterNode()
            emitter.particleTexture = dotTexture
            emitter.particleBirthRate = 10
            emitter.particleLifetime = 5
            emitter.particleLifetimeRange = 2
            emitter.particleSpeed = 18
            emitter.particleSpeedRange = 12
            emitter.emissionAngle = .pi / 2
            emitter.emissionAngleRange = .pi / 4
            emitter.particleScale = 0.035
            emitter.particleScaleRange = 0.025
            emitter.particleAlpha = 0.42
            emitter.particleAlphaRange = 0.22
            emitter.particleAlphaSpeed = -0.08
            emitter.particleColorBlendFactor = 1
            emitter.particlePositionRange = CGVector(dx: size.width, dy: 12)
            emitter.position = CGPoint(x: size.width / 2, y: -8)
            addChild(emitter)
            ambient = emitter
        }

        ambient?.particleColor = color.withAlphaComponent(0.85)
        ambient?.particlePositionRange = CGVector(dx: size.width, dy: 12)
        ambient?.position = CGPoint(x: size.width / 2, y: -8)
    }

    func confettiBurst(color: UIColor) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = dotTexture
        emitter.particleBirthRate = 700
        emitter.numParticlesToEmit = 90
        emitter.particleLifetime = 2.1
        emitter.particleLifetimeRange = 0.7
        emitter.particleSpeed = 165
        emitter.particleSpeedRange = 70
        emitter.emissionAngleRange = .pi * 2
        emitter.particleScale = 0.06
        emitter.particleScaleRange = 0.04
        emitter.particleAlpha = 0.92
        emitter.particleAlphaSpeed = -0.45
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.position = CGPoint(x: size.width / 2, y: size.height * 0.58)
        addChild(emitter)

        let cleanup = SKAction.sequence([
            .wait(forDuration: 2.8),
            .removeFromParent()
        ])
        emitter.run(cleanup)
    }

    private static func makeDotTexture() -> SKTexture {
        let size = CGSize(width: 18, height: 18)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }
}
