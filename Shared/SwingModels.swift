import Foundation

/// Ein Sensor-Sample der Watch. Bewusst Rohdaten (Gerätekoordinaten + Attitude),
/// damit die Rekonstruktion auf dem iPhone jederzeit neu gerechnet werden kann.
struct MotionSample: Codable {
    /// Sekunden seit Aufnahmebeginn
    var t: Double
    /// Attitude als Quaternion (Gerät relativ zum Referenzsystem, Z vertikal)
    var qx: Double, qy: Double, qz: Double, qw: Double
    /// userAcceleration in g, Gerätekoordinaten (Schwerkraft bereits entfernt)
    var ax: Double, ay: Double, az: Double
    /// rotationRate in rad/s, Gerätekoordinaten
    var gx: Double, gy: Double, gz: Double
}

struct SwingRecording: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var sampleRateHz: Double
    /// "batched-200Hz", "motionManager-100Hz" oder "demo"
    var source: String
    var samples: [MotionSample]
}
