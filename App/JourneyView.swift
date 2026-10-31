import SwiftUI
import SceneKit

/// Each level is one sculpted monument on a matte stepped plinth. Every rep adds the next piece
/// in build order; unearned pieces show as a faint silhouette so you can see the shape you're building.
@MainActor
final class MonumentScene {
    let scene = SCNScene()
    private let holder = SCNNode()
    private let camNode = SCNNode()
    private var key = ""

    init() {
        scene.rootNode.addChildNode(holder)
        let cam = SCNCamera()
        cam.fieldOfView = 30
        cam.projectionDirection = .horizontal
        cam.wantsHDR = true
        cam.bloomIntensity = 0.25
        cam.bloomThreshold = 0.95
        cam.wantsExposureAdaptation = false
        camNode.camera = cam
        scene.rootNode.addChildNode(camNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 1150
        key.light!.castsShadow = true
        key.light!.shadowRadius = 4
        key.light!.shadowSampleCount = 16
        key.light!.shadowMode = .deferred
        key.light!.shadowColor = NSColor.black.withAlphaComponent(0.6)
        key.eulerAngles = SCNVector3(-1.05, 0.75, 0)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light!.type = .directional
        rim.light!.intensity = 380
        rim.eulerAngles = SCNVector3(-0.3, -2.4, 0)
        scene.rootNode.addChildNode(rim)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .ambient
        fill.light!.intensity = 180
        scene.rootNode.addChildNode(fill)

        let turn = SCNAction.sequence([.rotateBy(x: 0, y: 0.35, z: 0, duration: 7), .rotateBy(x: 0, y: -0.35, z: 0, duration: 7)])
        turn.timingMode = .easeInEaseOut
        holder.runAction(.repeatForever(turn))
    }

    // MARK: Pieces

    enum Shape {
        case box(SCNVector3, SCNVector3)
        case pyramid(SCNVector3, CGFloat, CGFloat)
        case cone(SCNVector3, CGFloat, CGFloat)
        case cyl(SCNVector3, CGFloat, CGFloat)
        case gem(SCNVector3, CGFloat)
    }
    /// tone 0 = piece A, 1 = piece B, 2 = contrast accent
    struct Piece { let shape: Shape; let tone: Int }

    /// Build order for each level. The last piece is always the crown.
    static func blueprint(_ level: Int) -> [Piece] {
        func b(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ t: Int) -> Piece {
            Piece(shape: .box(SCNVector3(x, y + h / 2, z), SCNVector3(w, h, d)), tone: t)
        }
        switch level {
        case 0: // Spark: a seed stone that sprouts crystals
            return [
                b(0, 0, 0, 1.6, 0.5, 1.6, 1),
                Piece(shape: .pyramid(SCNVector3(0.15, 0.5, 0.1), 0.62, 2.3), tone: 0),
                Piece(shape: .pyramid(SCNVector3(-0.45, 0.5, 0.35), 0.4, 1.4), tone: 0),
                Piece(shape: .pyramid(SCNVector3(0.5, 0.5, -0.45), 0.34, 1.1), tone: 0),
                Piece(shape: .gem(SCNVector3(0.15, 3.3, 0.1), 0.28), tone: 2),
            ]
        case 1: // Foothills: a gateway of two pillars and a lintel
            return [
                b(-0.9, 0, 0, 0.55, 0.9, 0.55, 0), b(0.9, 0, 0, 0.55, 0.9, 0.55, 0),
                b(-0.9, 0.9, 0, 0.55, 0.9, 0.55, 1), b(0.9, 0.9, 0, 0.55, 0.9, 0.55, 1),
                b(0, 1.8, 0, 2.6, 0.35, 0.7, 0), b(0, 2.15, 0, 1.6, 0.25, 0.55, 1),
                Piece(shape: .gem(SCNVector3(0, 2.95, 0), 0.25), tone: 2),
            ]
        case 2: // Fog: a grove of cones, tallest in the middle
            let spots: [(CGFloat, CGFloat, CGFloat)] = [(0, 0, 2.4), (-0.85, 0.35, 1.5), (0.8, 0.45, 1.7), (-0.35, -0.75, 1.3), (0.55, -0.7, 1.1), (-1.1, -0.45, 0.9), (1.15, -0.2, 0.95)]
            return spots.enumerated().map { i, s in Piece(shape: .cone(SCNVector3(s.0, 0, s.1), 0.42, s.2), tone: i % 3 == 0 ? 1 : 0) }
                + [Piece(shape: .gem(SCNVector3(0, 3.1, 0), 0.24), tone: 2)]
        case 3: // The Long Field: a row of rising columns
            return (0..<8).map { i in
                b(-1.4 + CGFloat(i) * 0.4, 0, CGFloat(i % 2) * 0.25 - 0.12, 0.32, 0.45 + CGFloat(i) * 0.28, 0.32, i % 2)
            } + [Piece(shape: .gem(SCNVector3(1.4, 3.0, 0.13), 0.22), tone: 2)]
        case 4: // Storm: a twisting tower, stacked off-axis
            return (0..<9).map { i in
                let a = CGFloat(i) * 0.5
                return b(cos(a) * 0.18, CGFloat(i) * 0.36, sin(a) * 0.18, 1.1 - CGFloat(i) * 0.06, 0.34, 1.1 - CGFloat(i) * 0.06, i % 2)
            } + [Piece(shape: .gem(SCNVector3(0, 3.9, 0), 0.26), tone: 2)]
        case 5: // Ridge: a jagged range of pyramids
            let peaks: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0, 0, 0.9, 2.5), (-0.95, 0.2, 0.7, 1.7), (0.95, -0.1, 0.72, 1.9), (-0.4, 0.75, 0.5, 1.2), (0.5, 0.8, 0.5, 1.3), (-1.3, -0.6, 0.45, 1.0), (1.35, 0.55, 0.42, 1.0), (0.2, -0.85, 0.45, 1.1), (-0.75, -0.9, 0.4, 0.85)]
            return peaks.enumerated().map { i, p in Piece(shape: .pyramid(SCNVector3(p.0, 0, p.1), p.2, p.3), tone: i % 2) }
                + [Piece(shape: .gem(SCNVector3(0, 3.2, 0), 0.26), tone: 2)]
        case 6: // Ascent: a spiral stair around a core
            return [Piece(shape: .cyl(SCNVector3(0, 0, 0), 0.32, 3.6), tone: 1)] + (0..<10).map { i in
                let a = CGFloat(i) * 0.68
                return b(cos(a) * 0.85, CGFloat(i) * 0.34, sin(a) * 0.85, 0.62, 0.22, 0.42, 0)
            } + [Piece(shape: .gem(SCNVector3(0, 4.25, 0), 0.26), tone: 2)]
        default: // Peak: a stepped mountain crowned with the gem
            var out: [Piece] = []
            let steps: [(CGFloat, CGFloat, CGFloat)] = [(1.7, 0, 0.55), (1.32, 0.55, 0.55), (0.98, 1.1, 0.55), (0.66, 1.65, 0.55), (0.38, 2.2, 0.5)]
            for (i, s) in steps.enumerated() {
                out.append(Piece(shape: .box(SCNVector3(-s.0 / 4, s.1 + s.2 / 2, 0), SCNVector3(s.0 / 2, s.2, s.0)), tone: i % 2))
                out.append(Piece(shape: .box(SCNVector3(s.0 / 4, s.1 + s.2 / 2, 0), SCNVector3(s.0 / 2, s.2, s.0)), tone: (i + 1) % 2))
            }
            out.append(Piece(shape: .pyramid(SCNVector3(0, 2.7, 0), 0.4, 0.75), tone: 2))
            out.append(Piece(shape: .gem(SCNVector3(0, 4.15, 0), 0.38), tone: 0))
            return out
        }
    }

    /// Fits a blueprint to `count` reps. The crown is always the last piece; extra reps beyond
    /// the blueprint (long journeys) reuse its pieces in order.
    static func pieces(level: Int, count: Int) -> [Piece] {
        let all = blueprint(level)
        guard count > 1 else { return [all.last!] }
        if count <= all.count { return Array(all.prefix(count - 1)) + [all.last!] }
        return all
    }

    func show(level: Int, placed: Int, total: Int, skin: Skin, dust: Double) {
        let k = "\(level)-\(placed)-\(total)-\(skin.id)-\(Int(dust * 10))"
        guard k != key else { return }
        let animateLast = key.hasPrefix("\(level)-\(placed - 1)-\(total)-\(skin.id)")
        key = k
        holder.childNodes.forEach { $0.removeFromParentNode() }
        holder.particleSystems?.forEach { holder.removeParticleSystem($0) }
        scene.lightingEnvironment.contents = Mesh.environment(for: skin)
        scene.lightingEnvironment.intensity = 0.55

        let base = SCNBox(width: 4.6, height: 0.45, length: 4.6, chamferRadius: 0.04)
        base.materials = [Mesh.material(skin.plinth, roughness: 0.9)]
        let top = SCNBox(width: 3.9, height: 0.25, length: 3.9, chamferRadius: 0.03)
        top.materials = [Mesh.material(Self.lift(skin.plinth, 0.06), roughness: 0.85)]
        let n1 = SCNNode(geometry: base); n1.position = SCNVector3(0, -0.47, 0)
        let n2 = SCNNode(geometry: top); n2.position = SCNVector3(0, -0.125, 0)
        holder.addChildNode(n1); holder.addChildNode(n2)

        let list = Self.pieces(level: level, count: total)
        // with long journeys several reps map to one piece
        let shown = total <= list.count ? placed : Int((Double(placed) / Double(total) * Double(list.count)).rounded(.down))
        let a = Self.mute(skin.pieceA, dust), b = Self.mute(skin.pieceB, dust)
        let accent = Self.mute(skin.dark ? Color(hex: 0xF2F2EF) : Color(hex: 0x141414), dust)
        let ghostFill = SCNMaterial()
        ghostFill.lightingModel = .lambert
        ghostFill.diffuse.contents = NSColor(skin.fg).withAlphaComponent(0.06)
        ghostFill.transparency = 0.5
        ghostFill.writesToDepthBuffer = false
        ghostFill.blendMode = .alpha

        var maxY: CGFloat = 1
        for (i, p) in list.enumerated() {
            let on = i < shown
            let geo: SCNGeometry
            var pos: SCNVector3
            var isGem = false
            var scale = SCNVector3(1, 1, 1)
            switch p.shape {
            case .box(let c, let s):
                geo = SCNBox(width: s.x, height: s.y, length: s.z, chamferRadius: min(0.04, s.y * 0.1)); pos = c
                maxY = max(maxY, c.y + s.y / 2)
            case .pyramid(let c, let w, let h):
                geo = SCNPyramid(width: w * 2, height: h, length: w * 2); pos = c
                maxY = max(maxY, c.y + h)
            case .cone(let c, let r, let h):
                let cone = SCNCone(topRadius: 0, bottomRadius: r, height: h); cone.radialSegmentCount = 7
                geo = cone; pos = SCNVector3(c.x, c.y + h / 2, c.z)
                maxY = max(maxY, c.y + h)
            case .cyl(let c, let r, let h):
                let cy = SCNCylinder(radius: r, height: h); cy.radialSegmentCount = 8
                geo = cy; pos = SCNVector3(c.x, c.y + h / 2, c.z)
                maxY = max(maxY, c.y + h)
            case .gem(let c, let r):
                geo = Self.gemGeometry(); pos = c; isGem = true
                scale = SCNVector3(r, r * 1.6, r)
                maxY = max(maxY, c.y + r * 1.6)
            }
            if on {
                let color = p.tone == 0 ? a : p.tone == 1 ? b : accent
                geo.materials = [Mesh.material(color, roughness: isGem ? 0.12 : 0.42 + dust * 0.4, metalness: isGem ? 0.5 : 0.08,
                                               emission: isGem ? 0.35 : 0)]
            } else {
                geo.materials = [ghostFill]
            }
            let node = SCNNode(geometry: geo)
            node.position = pos
            node.scale = scale
            node.castsShadow = on
            holder.addChildNode(node)
            if isGem && on {
                node.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 6)))
                let bob = SCNAction.sequence([.moveBy(x: 0, y: 0.12, z: 0, duration: 1.6), .moveBy(x: 0, y: -0.12, z: 0, duration: 1.6)])
                bob.timingMode = .easeInEaseOut
                node.runAction(.repeatForever(bob))
            }
            if on && i == shown - 1 && animateLast {
                node.position.y += 2.2
                node.opacity = 0
                let drop = SCNAction.moveBy(x: 0, y: -2.2, z: 0, duration: 0.55)
                drop.timingMode = .easeIn
                node.runAction(.sequence([.wait(duration: 0.15), .group([drop, .fadeIn(duration: 0.25)]),
                                          .scale(to: 1.06, duration: 0.06), .scale(to: 1, duration: 0.1)]))
            }
        }

        // frame plinth to crown
        let mid = maxY / 2
        let dist = max(8.4, maxY * 1.5 + 4.2)
        camNode.position = SCNVector3(dist * 0.66, mid + dist * 0.4, dist * 0.66)
        camNode.look(at: SCNVector3(0, mid - 0.35, 0))

        if dust > 0 {
            let ps = SCNParticleSystem()
            ps.birthRate = CGFloat(30 * dust)
            ps.particleLifeSpan = 6
            ps.particleSize = 0.03
            ps.particleColor = NSColor(white: 0.85, alpha: 0.6)
            ps.emitterShape = SCNBox(width: 4, height: 3, length: 4, chamferRadius: 0)
            ps.particleVelocity = 0.06
            ps.isAffectedByGravity = false
            ps.blendMode = .additive
            holder.addParticleSystem(ps)
        }
    }

    private static func mute(_ c: Color, _ dust: Double) -> Color {
        guard dust > 0, let n = NSColor(c).usingColorSpace(.sRGB) else { return c }
        return Color(n.blended(withFraction: dust * 0.6, of: NSColor(white: 0.55, alpha: 1)) ?? n)
    }

    private static func lift(_ c: Color, _ by: CGFloat) -> Color {
        guard let n = NSColor(c).usingColorSpace(.sRGB) else { return c }
        return Color(n.blended(withFraction: by, of: .white) ?? n)
    }

    private static func gemGeometry() -> SCNGeometry {
        let v: [SCNVector3] = [SCNVector3(0, 1, 0), SCNVector3(1, 0, 0), SCNVector3(0, 0, 1), SCNVector3(-1, 0, 0), SCNVector3(0, 0, -1), SCNVector3(0, -1, 0)]
        let f: [Int] = [0, 2, 1, 0, 3, 2, 0, 4, 3, 0, 1, 4, 5, 1, 2, 5, 2, 3, 5, 3, 4, 5, 4, 1]
        var verts: [SCNVector3] = [], normals: [SCNVector3] = []
        for t in stride(from: 0, to: f.count, by: 3) {
            let a = v[f[t]], b = v[f[t + 1]], c = v[f[t + 2]]
            let u = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z), w = SCNVector3(c.x - a.x, c.y - a.y, c.z - a.z)
            var n = SCNVector3(u.y * w.z - u.z * w.y, u.z * w.x - u.x * w.z, u.x * w.y - u.y * w.x)
            let l = sqrt(n.x * n.x + n.y * n.y + n.z * n.z); n = SCNVector3(n.x / l, n.y / l, n.z / l)
            verts += [a, b, c]; normals += [n, n, n]
        }
        let idx = (0..<Int32(verts.count)).map { $0 }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }
}

struct JourneyView: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    let habit: Habit
    @State private var monument = MonumentScene()
    @State private var viewing: Int?

    var body: some View {
        let current = habit.level
        let level = viewing ?? current
        let need = habit.levelReps[level]
        let placed = habit.isMastered || level < current ? need : level == current ? habit.placedInLevel : 0
        let locked = level > current && !habit.isMastered
        HStack(spacing: 0) {
            ZStack {
                SceneKitView(scene: monument.scene, allowsCameraControl: true)
                if locked {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill").font(.system(size: 22, weight: .bold))
                        MonoCaps("Unlocks at rep \(Journey.levelStart(level, length: habit.journeyLength))", color: skin.fg)
                    }
                    .foregroundStyle(skin.fg)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(skin.bgBottom.opacity(0.8)))
                }
            }
            .frame(minWidth: 320)
            VStack(alignment: .leading, spacing: 14) {
                MonoCaps("Level \(level + 1) of 8 · \(placed) / \(need) pieces", color: skin.accent)
                Text(Journey.names[level]).font(.display(38)).foregroundStyle(skin.fg)
                Text(Journey.copy[level]).font(.body(15)).foregroundStyle(skin.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340, alignment: .leading)
                if habit.dust(today: store.today, after: store.settings.dustDays) > 0 {
                    Text("Dust has settled while you were away. One check clears it, and every piece is still here.")
                        .font(.body(13)).foregroundStyle(skin.accent)
                        .frame(maxWidth: 340, alignment: .leading)
                }
                Divider().overlay(skin.line).padding(.vertical, 6)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(0..<Journey.levelCount, id: \.self) { i in
                        Button { viewing = i } label: {
                            HStack(spacing: 10) {
                                Image(systemName: Journey.symbols[i]).frame(width: 18)
                                Text(Journey.names[i]).font(.body(13, i == level ? .bold : .regular))
                                Spacer(minLength: 0)
                                Text("\(Journey.cumulative(length: habit.journeyLength)[i])").font(.mono(10)).foregroundStyle(skin.fgDim)
                            }
                            .foregroundStyle(i == level ? skin.accent : skin.fg)
                            .opacity(i <= current || habit.isMastered ? 1 : 0.4)
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(i == level ? skin.fg.opacity(0.07) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 360)
                MonoCaps("Drag to orbit · scroll to zoom", size: 9).padding(.top, 4)
            }
            .padding(28)
            .frame(width: 400, alignment: .leading)
        }
        .onAppear { refresh(level: level, placed: placed, total: need) }
        .onChange(of: "\(level)-\(placed)-\(need)-\(skin.id)") { refresh(level: level, placed: placed, total: need) }
        .onChange(of: habit.id) { viewing = nil }
    }

    private func refresh(level: Int, placed: Int, total: Int) {
        monument.show(level: level, placed: placed, total: total, skin: skin,
                      dust: habit.dust(today: store.today, after: store.settings.dustDays))
    }
}
