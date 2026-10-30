import Foundation
import simd

/// Synthetischer Schwung mit bekannter Wahrheit: Handgelenk auf einem Kreis (r = 0,7 m)
/// in einer um 60° geneigten Schwungebene. Dient als Referenztest der Rekonstruktion
/// und zum Ausprobieren im Simulator ohne Watch.
enum DemoSwing {
    static let radius = 0.7
    static let planeTilt = 60.0 * .pi / 180

    /// Winkel im Schwungkreis: 0 = Ansprechen, negativ = Rückschwung, positiv = Durchschwung
    static func theta(_ t: Double) -> Double {
        func smooth(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
        if t < 0.5 { return 0 }
        if t < 1.4 { return -2.4 * smooth((t - 0.5) / 0.9) }          // Rückschwung, 0,9 s
        if t < 1.75 { return -2.4 + 5.0 * smooth((t - 1.4) / 0.35) }  // Abschwung + Durchschwung
        return 2.6                                                     // Finish halten
    }

    static func truePosition(_ t: Double) -> SIMD3<Double> {
        let th = theta(t)
        let u = SIMD3<Double>(1, 0, 0)                                  // Ziellinie
        let up = SIMD3<Double>(0, cos(planeTilt), sin(planeTilt))       // "oben" in der Ebene
        return radius * (sin(th) * u + (1 - cos(th)) * up)
    }

    static func make(rate: Double = 200, duration: Double = 2.6) -> SwingRecording {
        let dt = 1 / rate
        let n = Int(duration * rate)
        let normal = simd_normalize(simd_cross(SIMD3<Double>(1, 0, 0), SIMD3(0, cos(planeTilt), sin(planeTilt))))
        var samples: [MotionSample] = []
        for i in 0..<n {
            let t = Double(i) * dt
            // Beschleunigung per zentraler Differenz der wahren Position
            let a = (truePosition(t + dt) - 2 * truePosition(t) + truePosition(t - dt)) / (dt * dt) / SwingReconstructor.gravity
            let w = (theta(t + dt) - theta(t - dt)) / (2 * dt) * normal
            // Attitude = Identität: Gerätesystem = Referenzsystem
            samples.append(MotionSample(t: t, qx: 0, qy: 0, qz: 0, qw: 1,
                                        ax: a.x, ay: a.y, az: a.z,
                                        gx: w.x, gy: w.y, gz: w.z))
        }
        return SwingRecording(date: Date(), sampleRateHz: rate, source: "demo", samples: samples)
    }
}
