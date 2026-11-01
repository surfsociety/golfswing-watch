import SwiftUI
import SceneKit
import simd

/// 3D-Darstellung: Achsenkreuz (X rot, Y grün, Z/vertikal blau, je 1 m), Gitter auf Ansprechhöhe,
/// Bahn als Band, dessen Fläche der Uhrenoberseite folgt (die Verdrehung des Bandes zeigt die
/// Unterarmrotation), eingefärbt nach Handgelenk-Geschwindigkeit. Am Zeit-Marker hängt ein
/// stilisierter Arm: Schulter (fest, geschätzt), Oberarm, Ellbogen, Unterarm, ausgerichtete Uhr
/// (Display orange) und Hand.
struct SwingSceneView: UIViewRepresentable {
    let swing: ReconstructedSwing
    let progress: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .systemBackground
        view.antialiasingMode = .multisampling4X
        view.scene = context.coordinator.buildScene(for: swing)
        context.coordinator.updateMarker(progress: progress)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if context.coordinator.needsRebuild(for: swing) {
            view.scene = context.coordinator.buildScene(for: swing)
        }
        context.coordinator.updateMarker(progress: progress)
    }

    final class Coordinator {
        private var positions: [SCNVector3] = []
        private var orientations: [simd_quatf] = []
        private var elbows: [SIMD3<Float>] = []
        private var shoulder = SIMD3<Float>(0, 0, 0)
        private let marker = SCNNode()
        private let upperArm = Coordinator.limb(radius: 0.022)
        private let forearm = Coordinator.limb(radius: 0.018)
        private let shoulderJoint = Coordinator.joint(radius: 0.035)
        private let elbowJoint = Coordinator.joint(radius: 0.026)
        private var builtFor: (count: Int, distal: Double) = (0, 0)

        /// Referenzsystem der Watch: Z vertikal. SceneKit: Y oben. (x, y, z) → (x, z, −y),
        /// das ist eine Drehung um −90° um X.
        private let sceneFromReference = simd_quatd(angle: -.pi / 2, axis: SIMD3(1, 0, 0))

        private func toScene(_ p: SIMD3<Double>) -> SCNVector3 {
            SCNVector3(Float(p.x), Float(p.z), Float(-p.y))
        }

        private func toSceneSIMD(_ p: SIMD3<Double>) -> SIMD3<Float> {
            SIMD3(Float(p.x), Float(p.z), Float(-p.y))
        }

        func needsRebuild(for swing: ReconstructedSwing) -> Bool {
            builtFor.count != swing.points.count || builtFor.distal != swing.distalAxis.x
        }

        func buildScene(for swing: ReconstructedSwing) -> SCNScene {
            let scene = SCNScene()
            builtFor = (swing.points.count, swing.distalAxis.x)
            positions = swing.points.map { toScene($0.position) }
            orientations = swing.points.map { simd_quatf(vector: SIMD4<Float>((sceneFromReference * $0.attitude).vector)) }
            elbows = swing.points.map { toSceneSIMD($0.elbow) }
            shoulder = toSceneSIMD(swing.shoulder)

            scene.rootNode.addChildNode(axes())
            scene.rootNode.addChildNode(grid())

            let maxSpeed = max(swing.peakWristSpeed, 0.01)
            let colors = swing.points.map { SpeedColor.rgba($0.wristSpeed / maxSpeed) }
            scene.rootNode.addChildNode(SCNNode(geometry: ribbon(colors)))

            buildMarker(distalSign: Float(swing.distalAxis.x))
            scene.rootNode.addChildNode(marker)
            for node in [upperArm, forearm, shoulderJoint, elbowJoint] {
                scene.rootNode.addChildNode(node)
            }
            shoulderJoint.simdPosition = shoulder

            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.zNear = 0.01
            camera.position = SCNVector3(0, 0.8, 2.6)
            camera.look(at: SCNVector3(0, 0.6, 0))
            scene.rootNode.addChildNode(camera)
            return scene
        }

        func updateMarker(progress: Double) {
            guard !positions.isEmpty else { return }
            let i = Int((Double(positions.count - 1) * progress).rounded())
            marker.position = positions[i]
            marker.simdOrientation = orientations[i]
            let wrist = SIMD3<Float>(positions[i].x, positions[i].y, positions[i].z)
            elbowJoint.simdPosition = elbows[i]
            Coordinator.place(upperArm, from: shoulder, to: elbows[i])
            Coordinator.place(forearm, from: elbows[i], to: wrist)
        }

        /// Zylinder der Höhe 1 entlang Y; wird per Skalierung auf die Segmentlänge gebracht.
        private static func limb(radius: CGFloat) -> SCNNode {
            let cyl = SCNCylinder(radius: radius, height: 1)
            cyl.firstMaterial?.diffuse.contents = UIColor.systemGray2
            return SCNNode(geometry: cyl)
        }

        private static func joint(radius: CGFloat) -> SCNNode {
            let sphere = SCNSphere(radius: radius)
            sphere.firstMaterial?.diffuse.contents = UIColor.systemGray
            return SCNNode(geometry: sphere)
        }

        private static func place(_ node: SCNNode, from a: SIMD3<Float>, to b: SIMD3<Float>) {
            var d = b - a
            let length = simd_length(d)
            guard length > 1e-4 else { return }
            node.simdPosition = (a + b) / 2
            // Zylinder ist symmetrisch: Richtung nach oben drehen, um den 180°-Sonderfall zu vermeiden
            if d.y < 0 { d = -d }
            node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: d / length)
            node.simdScale = SIMD3(1, length, 1)
        }

        /// Uhr im Gerätesystem: X Richtung Krone, Y Richtung 12 Uhr, Z aus dem Display.
        private func buildMarker(distalSign: Float) {
            marker.childNodes.forEach { $0.removeFromParentNode() }
            let box = SCNBox(width: 0.06, height: 0.07, length: 0.02, chamferRadius: 0.006)
            let face = SCNMaterial(); face.diffuse.contents = UIColor.systemOrange
            let body = SCNMaterial(); body.diffuse.contents = UIColor.darkGray
            // Reihenfolge: vorne (+Z, Display), rechts, hinten, links, oben, unten
            box.materials = [face, body, body, body, body, body]
            marker.addChildNode(SCNNode(geometry: box))

            // Stilisierte Hand: Kugel jenseits des Handgelenks entlang der Unterarmachse
            let fist = SCNSphere(radius: 0.035)
            fist.firstMaterial?.diffuse.contents = UIColor.systemGray
            let hand = SCNNode(geometry: fist)
            hand.position = SCNVector3(distalSign * 0.08, 0, -0.02)
            marker.addChildNode(hand)
        }

        /// Band entlang der Bahn. Breitenrichtung = Geräte-Y (um das Handgelenk herum),
        /// sodass die Bandfläche zum Display zeigt.
        private func ribbon(_ colors: [SIMD4<Float>]) -> SCNGeometry {
            let halfWidth: Float = 0.02
            var verts: [SCNVector3] = []
            var vColors: [SIMD4<Float>] = []
            for (i, p) in positions.enumerated() {
                let side = orientations[i].act(SIMD3<Float>(0, 1, 0)) * halfWidth
                verts.append(SCNVector3(p.x - side.x, p.y - side.y, p.z - side.z))
                verts.append(SCNVector3(p.x + side.x, p.y + side.y, p.z + side.z))
                vColors += [colors[i], colors[i]]
            }
            var idx: [Int32] = []
            for i in 1..<Int32(positions.count) {
                let a = 2 * (i - 1), b = a + 1, c = a + 2, d = a + 3
                idx += [a, b, c, b, d, c]
            }
            let colorData = vColors.withUnsafeBufferPointer { Data(buffer: $0) }
            let cSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: vColors.count,
                                            usesFloatComponents: true, componentsPerVector: 4,
                                            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                            dataStride: MemoryLayout<SIMD4<Float>>.stride)
            let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), cSource],
                                  elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            geo.materials = [mat]
            return geo
        }

        private func axes() -> SCNNode {
            let node = SCNNode()
            let specs: [(UIColor, SCNVector3, SCNVector3)] = [
                (.systemRed, SCNVector3(0.5, 0, 0), SCNVector3(0, 0, Float.pi / 2)),   // X
                (.systemGreen, SCNVector3(0, 0, -0.5), SCNVector3(Float.pi / 2, 0, 0)), // Y (Referenz) → −Z (Scene)
                (.systemBlue, SCNVector3(0, 0.5, 0), SCNVector3(0, 0, 0))               // Z vertikal → Y (Scene)
            ]
            for (color, pos, rot) in specs {
                let cyl = SCNCylinder(radius: 0.004, height: 1)
                cyl.firstMaterial?.diffuse.contents = color
                let n = SCNNode(geometry: cyl)
                n.position = pos
                n.eulerAngles = rot
                node.addChildNode(n)
            }
            return node
        }

        private func grid() -> SCNNode {
            var verts: [SCNVector3] = []
            for k in stride(from: -1.5, through: 1.5, by: 0.25) {
                let f = Float(k)
                verts += [SCNVector3(f, -0.001, -1.5), SCNVector3(f, -0.001, 1.5),
                          SCNVector3(-1.5, -0.001, f), SCNVector3(1.5, -0.001, f)]
            }
            let el = SCNGeometryElement(indices: Array(0..<Int32(verts.count)), primitiveType: .line)
            let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts)], elements: [el])
            geo.firstMaterial?.diffuse.contents = UIColor.tertiaryLabel
            geo.firstMaterial?.lightingModel = .constant
            return SCNNode(geometry: geo)
        }
    }
}
