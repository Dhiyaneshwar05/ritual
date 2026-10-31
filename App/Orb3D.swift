import SwiftUI
import SceneKit
import AppKit

// MARK: - Shared 3D helpers

enum Mesh {
    /// The check outline extruded into a solid, centered on the origin, roughly 1 unit wide.
    static func check(depth: CGFloat = 0.26) -> SCNGeometry {
        let p = NSBezierPath()
        let pts = CheckShape.points.map { CGPoint(x: ($0.x - 50) / 70, y: (50 - $0.y) / 70) }
        p.move(to: pts[0])
        pts.dropFirst().forEach { p.line(to: $0) }
        p.close()
        let shape = SCNShape(path: p, extrusionDepth: depth)
        shape.chamferRadius = 0.025
        shape.chamferMode = .both
        return shape
    }

    static func color(_ c: Color) -> NSColor { NSColor(c).usingColorSpace(.sRGB) ?? .gray }

    static func material(_ c: Color, roughness: Double = 0.5, metalness: Double = 0, emission: Double = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color(c)
        m.roughness.contents = NSNumber(value: roughness)
        m.metalness.contents = NSNumber(value: metalness)
        if emission > 0 {
            m.emission.contents = color(c)
            m.emission.intensity = emission
        }
        return m
    }

    /// A soft studio environment so glossy surfaces have something to reflect.
    static func environment(for skin: Skin) -> NSImage {
        let w = 512, h = 256
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        let top = skin.dark ? NSColor(white: 0.32, alpha: 1) : NSColor(white: 0.98, alpha: 1)
        let mid = skin.dark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 0.7, alpha: 1)
        let bottom = skin.dark ? NSColor(white: 0.02, alpha: 1) : NSColor(white: 0.35, alpha: 1)
        NSGradient(colors: [bottom, mid, top], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
        // two soft-box highlights for crisp reflections
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: NSRect(x: 150, y: 190, width: 110, height: 34), xRadius: 16, yRadius: 16).fill()
        NSColor.white.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: NSRect(x: 360, y: 150, width: 60, height: 60), xRadius: 30, yRadius: 30).fill()
        NSColor(skin.accent).withAlphaComponent(skin.dark ? 0.35 : 0.2).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 70, width: w, height: 18)).fill()
        img.unlockFocus()
        return img
    }
}

// MARK: - Orb scene

/// Owns the SceneKit graph for the orb so SwiftUI can drive it with hold progress and events.
@MainActor
final class OrbScene {
    let scene = SCNScene()
    private let root = SCNNode()
    private let floatNode = SCNNode()
    private let orb = SCNNode()
    private let check = SCNNode()
    private let shell = SCNNode()
    private var skinID = ""
    private(set) var isDone = false

    init() {
        scene.rootNode.addChildNode(root)
        root.addChildNode(floatNode)
        floatNode.addChildNode(orb)
        floatNode.addChildNode(check)

        let cam = SCNCamera()
        cam.fieldOfView = 26
        cam.wantsHDR = true
        cam.bloomIntensity = 0.6
        cam.bloomThreshold = 0.85
        cam.bloomBlurRadius = 14
        cam.wantsExposureAdaptation = false
        cam.vignettingIntensity = 0
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0, 6.2) // sphere spans ~1/1.4 of the view; the margin is room for shards
        scene.rootNode.addChildNode(camNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 900
        key.eulerAngles = SCNVector3(-0.7, -0.5, 0)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light!.type = .directional
        rim.light!.intensity = 500
        rim.eulerAngles = SCNVector3(0.4, 2.6, 0)
        scene.rootNode.addChildNode(rim)

        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 96
        orb.geometry = sphere

        check.geometry = Mesh.check()
        check.scale = SCNVector3(0.001, 0.001, 0.001)
        check.opacity = 0
        // isometric tilt like a toy block
        check.eulerAngles = SCNVector3(-0.35, 0.55, 0.0)
        check.position = SCNVector3(0.02, -0.02, 1.12)

        let bob = SCNAction.sequence([
            .moveBy(x: 0, y: 0.04, z: 0, duration: 2.4),
            .moveBy(x: 0, y: -0.04, z: 0, duration: 2.4),
        ])
        bob.timingMode = .easeInEaseOut
        floatNode.runAction(.repeatForever(bob))
        let sway = SCNAction.sequence([
            .rotateTo(x: 0.05, y: 0.12, z: 0, duration: 3.2),
            .rotateTo(x: -0.03, y: -0.12, z: 0, duration: 3.2),
        ])
        sway.timingMode = .easeInEaseOut
        floatNode.runAction(.repeatForever(sway))
    }

    func apply(skin: Skin) {
        guard skin.id != skinID else { return }
        skinID = skin.id
        scene.lightingEnvironment.contents = Mesh.environment(for: skin)
        scene.lightingEnvironment.intensity = skin.dark ? 1.1 : 1.4
        scene.background.contents = NSColor.clear

        let m = Mesh.material(skin.orbBase, roughness: skin.orbRoughness, metalness: skin.orbMetalness)
        if skin.iridescence > 0 {
            // Oil-slick fresnel rim: hue rotates with view angle and surface direction.
            m.shaderModifiers = [.fragment: """
            float3 n = normalize(_surface.normal);
            float3 v = normalize(_surface.view);
            float f = smoothstep(0.55, 1.0, 1.0 - saturate(dot(n, v)));
            float h = atan2(n.y, n.x) * 0.159 + 0.5 + n.z * 0.15;
            float3 rgb = saturate(abs(fract(h + float3(0.0, 0.333, 0.667)) * 6.0 - 3.0) - 1.0);
            _output.color.rgb += rgb * f * f * \(String(format: "%.2f", skin.iridescence * 1.3));
            """]
        }
        if skin.glass {
            m.transparency = 0.82
            m.transparencyMode = .dualLayer
            m.isDoubleSided = false
            m.shaderModifiers = [.fragment: """
            float3 n = normalize(_surface.normal);
            float3 v = normalize(_surface.view);
            float f = pow(1.0 - saturate(dot(n, v)), 2.0);
            float h = n.y * 0.25 + 0.75;
            float3 rgb = saturate(abs(fract(h + float3(0.0, 0.333, 0.667)) * 6.0 - 3.0) - 1.0);
            _output.color.rgb += mix(float3(1.0), rgb, 0.5) * f * 0.9;
            """]
        }
        orb.geometry?.materials = [m]

        let face = Mesh.material(skin.checkFace, roughness: 0.42, emission: skin.glow > 0 ? 0.6 : 0.28)
        let side = Mesh.material(skin.checkSide, roughness: 0.55)
        // SCNShape material order: front, back, sides (plus chamfers).
        check.geometry?.materials = [face, face, side, side, side]
    }

    func setDone(_ done: Bool, animated: Bool) {
        isDone = done
        check.removeAllActions()
        if done {
            if animated {
                check.runAction(.group([
                    .fadeIn(duration: 0.12),
                    .sequence([
                        .scale(to: 0.62 * 1.25, duration: 0.18),
                        .scale(to: 0.62 * 0.95, duration: 0.12),
                        .scale(to: 0.62, duration: 0.1),
                    ]),
                ]))
            } else {
                check.opacity = 1
                check.scale = SCNVector3(0.62, 0.62, 0.62)
            }
        } else {
            check.runAction(.group([.fadeOut(duration: animated ? 0.15 : 0), .scale(to: 0.001, duration: animated ? 0.15 : 0)]))
        }
    }

    /// 0…1 while the user holds. Squashes and pushes the orb back a little.
    func setHold(_ p: Double) {
        let s = CGFloat(1 - 0.07 * p)
        root.scale = SCNVector3(s, s, s)
        root.position = SCNVector3(0, 0, CGFloat(-0.15 * p))
    }

    func celebrate(skin: Skin, big: Bool, count: Int? = nil) {
        root.removeAction(forKey: "pop")
        root.scale = SCNVector3(1, 1, 1)
        root.position = SCNVector3Zero
        let pop = SCNAction.sequence([.scale(to: 1.1, duration: 0.12), .scale(to: 0.97, duration: 0.12), .scale(to: 1, duration: 0.14)])
        root.runAction(pop, forKey: "pop")
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: big ? 1.1 : 0.7)
        spin.timingMode = .easeOut
        orb.runAction(spin)
        burst(skin: skin, count: count ?? (big ? 90 : 48))
    }

    /// Faceted shards fly out of the orb and fall away.
    private func burst(skin: Skin, count: Int) {
        let a = Mesh.material(skin.shardA, roughness: 0.3, emission: 0.25)
        let b = Mesh.material(skin.shardB, roughness: 0.3, emission: 0.15)
        for i in 0..<count {
            let size = CGFloat.random(in: 0.05...0.13)
            let g = SCNPyramid(width: size, height: size * 1.6, length: size)
            g.materials = [i % 3 == 0 ? b : a]
            let n = SCNNode(geometry: g)
            let theta = Double.random(in: 0..<(2 * .pi))
            let phi = Double.random(in: -0.9...0.9)
            let dir = SCNVector3(CGFloat(cos(theta) * cos(phi)), CGFloat(sin(theta) * cos(phi)), CGFloat(abs(sin(phi)) + 0.3))
            n.position = SCNVector3(dir.x * 0.95, dir.y * 0.95, dir.z * 0.6)
            n.eulerAngles = SCNVector3(.random(in: 0...6), .random(in: 0...6), .random(in: 0...6))
            scene.rootNode.addChildNode(n)
            let dist = CGFloat.random(in: 1.0...2.2)
            let t = Double.random(in: 0.7...1.2)
            let out = SCNAction.moveBy(x: dir.x * dist, y: dir.y * dist + 0.4, z: dir.z * dist * 0.6, duration: t * 0.55)
            out.timingMode = .easeOut
            let fall = SCNAction.moveBy(x: dir.x * 0.2, y: -1.4, z: 0, duration: t * 0.45)
            fall.timingMode = .easeIn
            n.runAction(.sequence([
                .group([.sequence([out, fall]),
                        .rotateBy(x: .random(in: -8...8), y: .random(in: -8...8), z: .random(in: -8...8), duration: t),
                        .sequence([.wait(duration: t * 0.6), .fadeOut(duration: t * 0.4)])]),
                .removeFromParentNode(),
            ]))
        }
    }

    func nudge() {
        let shake = SCNAction.sequence([
            .rotateBy(x: 0, y: 0, z: 0.08, duration: 0.05), .rotateBy(x: 0, y: 0, z: -0.16, duration: 0.1),
            .rotateBy(x: 0, y: 0, z: 0.08, duration: 0.05),
        ])
        root.runAction(shake)
    }
}

// MARK: - SwiftUI bridge

struct SceneKitView: NSViewRepresentable {
    let scene: SCNScene
    var allowsCameraControl = false
    var antialiasing: SCNAntialiasingMode = .multisampling4X

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        v.scene = scene
        v.backgroundColor = .clear
        v.wantsLayer = true
        v.layer?.isOpaque = false
        v.antialiasingMode = antialiasing
        v.isPlaying = true
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        v.allowsCameraControl = allowsCameraControl
        if allowsCameraControl {
            v.defaultCameraController.interactionMode = .orbitTurntable
            v.defaultCameraController.inertiaEnabled = true
            v.defaultCameraController.maximumVerticalAngle = 40
            v.defaultCameraController.minimumVerticalAngle = -5
        }
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        if v.scene !== scene { v.scene = scene }
    }
}
