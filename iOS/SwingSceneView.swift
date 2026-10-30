import SwiftUI
import SceneKit

/// 3D-Darstellung: Achsenkreuz (X rot, Y grün, Z/vertikal blau, je 1 m), Bodengitter,
/// Bahn als Linie + Punkte, eingefärbt nach Handgelenk-Geschwindigkeit, plus Marker für den Slider.
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
        if context.coordinator.pointCount != swing.points.count {
            view.scene = context.coordinator.buildScene(for: swing)
        }
        context.coordinator.updateMarker(progress: progress)
    }

    final class Coordinator {
        private var positions: [SCNVector3] = []
        private let marker = SCNNode(geometry: SCNSphere(radius: 0.025))
        var pointCount = 0

        /// Referenzsystem der Watch: Z vertikal. SceneKit: Y oben. (x, y, z) → (x, z, -y)
        private func toScene(_ p: SIMD3<Double>) -> SCNVector3 {
            SCNVector3(Float(p.x), Float(p.z), Float(-p.y))
        }

        func buildScene(for swing: ReconstructedSwing) -> SCNScene {
            let scene = SCNScene()
            positions = swing.points.map { toScene($0.position) }
            pointCount = positions.count

            scene.rootNode.addChildNode(axes())
            scene.rootNode.addChildNode(grid())

            let maxSpeed = max(swing.peakWristSpeed, 0.01)
            let colors = swing.points.map { SpeedColor.rgba($0.wristSpeed / maxSpeed) }
            scene.rootNode.addChildNode(SCNNode(geometry: trajectoryGeometry(positions, colors)))

            marker.geometry?.firstMaterial?.diffuse.contents = UIColor.label
            scene.rootNode.addChildNode(marker)

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
        }

        private func trajectoryGeometry(_ verts: [SCNVector3], _ colors: [SIMD4<Float>]) -> SCNGeometry {
            let vSource = SCNGeometrySource(vertices: verts)
            let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            let cSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count,
                                            usesFloatComponents: true, componentsPerVector: 4,
                                            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                            dataStride: MemoryLayout<SIMD4<Float>>.stride)
            var lineIdx: [Int32] = []
            for i in 1..<Int32(verts.count) { lineIdx += [i - 1, i] }
            let lines = SCNGeometryElement(indices: lineIdx, primitiveType: .line)
            let points = SCNGeometryElement(indices: Array(0..<Int32(verts.count)), primitiveType: .point)
            points.pointSize = 6
            points.minimumPointScreenSpaceRadius = 2
            points.maximumPointScreenSpaceRadius = 6

            let geo = SCNGeometry(sources: [vSource, cSource], elements: [lines, points])
            geo.materials = [SCNMaterial(), SCNMaterial()]
            geo.materials.forEach { $0.lightingModel = .constant }
            return geo
        }

        private func axes() -> SCNNode {
            let node = SCNNode()
            let specs: [(UIColor, SCNVector3, SCNVector3)] = [
                (.systemRed, SCNVector3(0.5, 0, 0), SCNVector3(0, 0, Float.pi / 2)),   // X
                (.systemGreen, SCNVector3(0, 0, -0.5), SCNVector3(Float.pi / 2, 0, 0)), // Y (Referenz) → -Z (Scene)
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
