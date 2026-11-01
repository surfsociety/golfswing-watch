import Foundation
import simd

enum GripStyle: String, CaseIterable, Identifiable {
    case weak, neutral, strong
    var id: String { rawValue }
    var label: String {
        switch self {
        case .weak: "Schwach"
        case .neutral: "Neutral"
        case .strong: "Stark"
        }
    }
    /// Drehung der Hand am Schaft gegenüber neutral, in Grad. Positiv = stärker.
    /// Schätzwert für die Darstellung, keine Messung.
    var rotationDeg: Double {
        switch self {
        case .weak: -25
        case .neutral: 0
        case .strong: 25
        }
    }
}

/// Handhaltung beim Ansprechen. Die Uhr misst nur den Unterarm; die Hand wird in dieser Pose
/// starr am Unterarm befestigt und geht mit. Beugen/Strecken/Abwinkeln im Schwung bleibt ungemessen.
struct HandPose: Equatable {
    /// Rechtshänder spielen mit der linken Hand als Führungshand
    var golferRightHanded = true
    var grip: GripStyle = .neutral
    /// Winkel zwischen Unterarmachse und Schaft beim Ansprechen (Abweichung von der Geraden), Grad
    var shaftAngleDeg = 30.0

    func watchOnLeadHand(wrist: Side) -> Bool {
        (wrist == .left) == golferRightHanded
    }
}

struct HandSegment {
    enum Kind { case skin, shaft, face }
    var from: SIMD3<Float>
    var to: SIMD3<Float>
    var radius: Float
    var kind: Kind
}

struct HandGeometry {
    var segments: [HandSegment]
    var palmCenter: SIMD3<Float>
    /// Spalten: Handachse (zu den Fingern), Daumenseite, Handrücken
    var palmBasis: simd_float3x3
    var palmSize: SIMD3<Float>
}

/// Stilisierte Hand im Griff, im Gerätesystem der Uhr.
///
/// Modelliert wird eine linke Hand in einem Hand-System (X zu den Fingern, Y zur Daumenseite,
/// Z Handrücken), das bei linkem Handgelenk und Krone zur Hand mit dem Gerätesystem übereinstimmt.
/// Rechtes Handgelenk = Spiegelung an der X-Z-Ebene, umgedrehte Uhr = 180° um Z.
enum HandModel {
    /// Winkel des Schafts zur Handachse in der Handfläche (diagonal durch die Finger), Schätzwert
    static let inHandShaftAngleDeg = 50.0
    /// Handgelenk-Mittelpunkt relativ zur Uhrenmitte
    static let wristJoint = SIMD3<Float>(0.025, 0, -0.025)

    static func geometry(pose: HandPose, wrist: Side, distalSign: Float) -> HandGeometry {
        let beta = Float(inHandShaftAngleDeg * .pi / 180)
        // Handgelenkstellung beim Ansprechen: Hand um die Handrücken-Achse gedreht, sodass der
        // Schaft den gewünschten Winkel zum Unterarm hat
        let delta = Float(pose.shaftAngleDeg * .pi / 180) - beta
        let handRot = simd_quatf(angle: delta, axis: SIMD3(0, 0, 1))
        let mirrorY: Float = wrist == .left ? 1 : -1
        func dir(_ v: SIMD3<Float>) -> SIMD3<Float> {
            let r = handRot.act(v)
            return SIMD3(distalSign * r.x, distalSign * mirrorY * r.y, r.z)
        }
        func pt(_ p: SIMD3<Float>) -> SIMD3<Float> {
            let r = handRot.act(p) + wristJoint
            return SIMD3(distalSign * r.x, distalSign * mirrorY * r.y, r.z)
        }

        var segs: [HandSegment] = []
        func skin(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ r: Float) {
            segs.append(HandSegment(from: pt(a), to: pt(b), radius: r, kind: .skin))
        }

        // Schaft (Griffstück) diagonal unter den Fingern, Schlägerkopf-Richtung zur Daumenseite
        let e = SIMD3<Float>(cos(beta), sin(beta), 0)
        let c = SIMD3<Float>(0.085, 0, -0.04)
        let butt = c - 0.08 * e
        let head = c + 0.25 * e
        segs.append(HandSegment(from: pt(butt), to: pt(head), radius: 0.012, kind: .shaft))

        // Vier Finger um den Schaft (Zeigefinger … kleiner Finger)
        for y: Float in [0.03, 0.01, -0.01, -0.03] {
            let s = c + (y / sin(beta)) * e
            let knuckle = SIMD3<Float>(0.095, y, -0.01)
            let p2 = s + SIMD3(0.022, 0, 0)
            let p3 = s + SIMD3(0, 0, -0.022)
            let p4 = s + SIMD3(-0.018, 0, -0.012)
            skin(knuckle, p2, 0.0085)
            skin(p2, p3, 0.0085)
            skin(p3, p4, 0.008)
        }
        // Daumen liegt oben auf dem Schaft und zeigt Richtung Schlägerkopf
        let thumbBase = SIMD3<Float>(0.02, 0.04, -0.01)
        let thumbTip = c + 0.06 * e + SIMD3(0, 0, 0.018)
        skin(thumbBase, thumbTip, 0.011)

        // Schlagflächen-Marker am Schaftende: Führungshand neutral = Handrücken-Richtung,
        // hintere Hand neutral = Handflächen-Richtung. Griffstärke dreht die Hand am Schaft,
        // also den Schläger relativ zur Hand in Gegenrichtung.
        let lead = pose.watchOnLeadHand(wrist: wrist)
        let n0 = SIMD3<Float>(0, 0, lead ? 1 : -1)
        let gripRot = simd_quatf(angle: -Float(pose.grip.rotationDeg * .pi / 180), axis: e)
        let n = gripRot.act(n0)
        segs.append(HandSegment(from: pt(head), to: pt(head + 0.05 * n), radius: 0.006, kind: .face))

        // Handteller
        let x = dir(SIMD3(1, 0, 0))
        let z = dir(SIMD3(0, 0, 1))
        let basis = simd_float3x3(columns: (x, simd_cross(z, x), z))
        return HandGeometry(segments: segs,
                            palmCenter: pt(SIMD3(0.05, 0, -0.005)),
                            palmBasis: basis,
                            palmSize: SIMD3(0.09, 0.085, 0.028))
    }
}
