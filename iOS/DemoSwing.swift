import Foundation
import simd

/// Synthetischer Schwung mit bekannter Wahrheit: linkes Handgelenk (Krone zur Hand) auf einem Kreis
/// (r = Ober- + Unterarm = 0,58 m, Schulter im Mittelpunkt, Arm gestreckt) in einer um 60° geneigten
/// Schwungebene. Der Unterarm zeigt immer vom Kreismittelpunkt
/// zum Handgelenk und rollt zusätzlich um die eigene Achse. Dient als Referenztest der Rekonstruktion
/// und zum Ausprobieren im Simulator ohne Watch.
enum DemoSwing {
    static let radius = ArmModel.forearmLength + ArmModel.upperArmLength
    static let planeTilt = 60.0 * .pi / 180
    static let targetLine = SIMD3<Double>(1, 0, 0)
    static let planeUp = SIMD3<Double>(0, cos(planeTilt), sin(planeTilt))
    static let planeNormal = simd_normalize(simd_cross(targetLine, planeUp))

    /// Winkel im Schwungkreis: 0 = Ansprechen, negativ = Rückschwung, positiv = Durchschwung
    static func theta(_ t: Double) -> Double {
        func smooth(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
        if t < 0.5 { return 0 }
        if t < 1.4 { return -2.4 * smooth((t - 0.5) / 0.9) }          // Rückschwung, 0,9 s
        if t < 1.75 { return -2.4 + 5.0 * smooth((t - 1.4) / 0.35) }  // Abschwung + Durchschwung
        return 2.6                                                     // Finish halten
    }

    /// Rollen des Unterarms um die eigene Achse (rad, positiv um +X = Richtung Hand).
    /// Am linken Arm ist das Pronation: im Rückschwung −69° (Supination), im Finish +74° (Pronation).
    static func roll(_ t: Double) -> Double { 0.5 * theta(t) }

    static func truePosition(_ t: Double) -> SIMD3<Double> {
        let th = theta(t)
        return radius * (sin(th) * targetLine + (1 - cos(th)) * planeUp)
    }

    /// Gerät → Referenz. Geräte-X zeigt entlang des Unterarms zur Hand.
    static func attitude(_ t: Double) -> simd_quatd {
        let base = simd_quatd(from: SIMD3(1, 0, 0), to: -planeUp)
        return simd_quatd(angle: theta(t), axis: planeNormal) * base * simd_quatd(angle: roll(t), axis: SIMD3(1, 0, 0))
    }

    static func make(rate: Double = 200, duration: Double = 2.6) -> SwingRecording {
        let dt = 1 / rate
        let n = Int(duration * rate)
        var samples: [MotionSample] = []
        for i in 0..<n {
            let t = Double(i) * dt
            let q = attitude(t)
            // Beschleunigung per zentraler Differenz, dann ins Gerätesystem
            let aRef = (truePosition(t + dt) - 2 * truePosition(t) + truePosition(t - dt)) / (dt * dt)
            let a = q.inverse.act(aRef) / SwingReconstructor.gravity
            // Drehrate im Gerätesystem aus der Attitude-Änderung (Kleinwinkelnäherung)
            var dq = attitude(t - dt).inverse * attitude(t + dt)
            if dq.real < 0 { dq = simd_quatd(vector: -dq.vector) }
            let w = dq.imag / dt
            samples.append(MotionSample(t: t, qx: q.imag.x, qy: q.imag.y, qz: q.imag.z, qw: q.real,
                                        ax: a.x, ay: a.y, az: a.z,
                                        gx: w.x, gy: w.y, gz: w.z))
        }
        return SwingRecording(date: Date(), sampleRateHz: rate, source: "demo", samples: samples,
                              wrist: .left, crown: .right)
    }
}
