import Foundation
import simd

struct SwingPoint {
    var t: Double
    /// Position des Handgelenks in Metern, relativ zur Ansprechposition. Z = vertikal.
    var position: SIMD3<Double>
    /// Geschwindigkeit des Handgelenks in m/s
    var wristSpeed: Double
    /// Grobe Schlägerkopf-Schätzung: |ω| · Hebellänge, in m/s
    var clubSpeedEstimate: Double
}

struct ReconstructedSwing {
    var points: [SwingPoint]
    var peakWristSpeed: Double
    var peakClubSpeedEstimate: Double
    /// Zeitpunkt der maximalen Winkelgeschwindigkeit (≈ Treffmoment), relativ zum Fensterstart
    var peakTime: Double
    /// true, wenn vor und nach dem Schwung eine Ruhephase gefunden wurde.
    /// Nur dann ist die Drift-Korrektur physikalisch begründet.
    var restDetectedAtBothEnds: Bool
}

/// Rekonstruiert die Handgelenk-Bahn aus Attitude + userAcceleration.
///
/// Pipeline:
/// 1. Schwung segmentieren: Peak der Winkelgeschwindigkeit, dann in beide Richtungen bis zur Ruhe.
/// 2. userAcceleration per Attitude-Quaternion ins Referenzsystem drehen (Z vertikal), g → m/s².
/// 3. Doppelte Integration (Trapez). Gegen Drift: Randbedingung v = 0 am Start (Ansprechen)
///    und am Ende (Finish halten); der lineare Restfehler wird von v abgezogen.
///
/// Grenzen: Die Drift wächst quadratisch mit der Zeit. Bei ~2–3 s Schwungdauer und der
/// Ruhe-Randbedingung ist die Form brauchbar, absolute Positionen bleiben auf einige cm unsicher.
enum SwingReconstructor {
    static let gravity = 9.80665

    static func reconstruct(_ recording: SwingRecording, clubLeverMeters: Double = 1.5) -> ReconstructedSwing? {
        let s = recording.samples
        guard s.count > 50 else { return nil }

        let omega = s.map { sqrt($0.gx * $0.gx + $0.gy * $0.gy + $0.gz * $0.gz) }
        let times = s.map(\.t)
        guard let peak = omega.indices.max(by: { omega[$0] < omega[$1] }) else { return nil }

        let (start, restBefore) = findRest(omega, times, from: peak, step: -1, maxSpan: 3.0)
        let (end, restAfter) = findRest(omega, times, from: peak, step: +1, maxSpan: 2.5)
        guard end - start > 10 else { return nil }
        let w = Array(s[start...end])

        // 2. Beschleunigung ins Referenzsystem
        let acc: [SIMD3<Double>] = w.map { m in
            let q = simd_quatd(ix: m.qx, iy: m.qy, iz: m.qz, r: m.qw)
            return q.act(SIMD3(m.ax, m.ay, m.az)) * gravity
        }

        // 3a. Geschwindigkeit
        var v = [SIMD3<Double>](repeating: .zero, count: w.count)
        for i in 1..<w.count {
            let dt = w[i].t - w[i - 1].t
            v[i] = v[i - 1] + 0.5 * (acc[i] + acc[i - 1]) * dt
        }
        // 3b. Drift-Korrektur (lineare Rampe, sodass v(Ende) = 0)
        let t0 = w[0].t
        let duration = max(w[w.count - 1].t - t0, 1e-6)
        let vEnd = v[v.count - 1]
        for i in v.indices {
            v[i] -= vEnd * ((w[i].t - t0) / duration)
        }
        // 3c. Position
        var p = [SIMD3<Double>](repeating: .zero, count: w.count)
        for i in 1..<w.count {
            let dt = w[i].t - w[i - 1].t
            p[i] = p[i - 1] + 0.5 * (v[i] + v[i - 1]) * dt
        }

        let points = w.indices.map { i in
            SwingPoint(t: w[i].t - t0,
                       position: p[i],
                       wristSpeed: simd_length(v[i]),
                       clubSpeedEstimate: omega[start + i] * clubLeverMeters)
        }
        return ReconstructedSwing(
            points: points,
            peakWristSpeed: points.map(\.wristSpeed).max() ?? 0,
            peakClubSpeedEstimate: omega[peak] * clubLeverMeters,
            peakTime: times[peak] - t0,
            restDetectedAtBothEnds: restBefore && restAfter)
    }

    /// Läuft vom Peak weg, bis |ω| für `hold` Sekunden unter `threshold` liegt.
    private static func findRest(_ omega: [Double], _ times: [Double], from idx: Int, step: Int,
                                 threshold: Double = 0.6, hold: Double = 0.25,
                                 maxSpan: Double) -> (index: Int, found: Bool) {
        var i = idx
        var quietSince: Int?
        while true {
            let next = i + step
            guard next >= 0, next < omega.count, abs(times[next] - times[idx]) <= maxSpan else {
                return (i, false)
            }
            i = next
            if omega[i] < threshold {
                if quietSince == nil { quietSince = i }
                if abs(times[i] - times[quietSince!]) >= hold { return (i, true) }
            } else {
                quietSince = nil
            }
        }
    }
}
