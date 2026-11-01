import SwiftUI
import Charts

struct SwingDetailView: View {
    let recording: SwingRecording
    /// "auto" = aus den Watch-Einstellungen der Aufnahme, sonst "left"/"right"
    @AppStorage("wristSetting") private var wristSetting = "auto"
    @State private var scrub = 1.0

    private var swing: ReconstructedSwing? {
        SwingReconstructor.reconstruct(recording, wristOverride: Side(rawValue: wristSetting))
    }

    var body: some View {
        if let swing {
            let current = swing.points[Int((Double(swing.points.count - 1) * scrub).rounded())]
            VStack(spacing: 0) {
                SwingSceneView(swing: swing, progress: scrub)
                    .ignoresSafeArea(edges: .horizontal)
                VStack(alignment: .leading, spacing: 8) {
                    if !swing.restDetectedAtBothEnds {
                        Label("Keine Ruhephase vor/nach dem Schwung erkannt – Bahn ist unzuverlässig.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    let upper = swing.upperArmLengthRange
                    Text(String(format: "Arm stilisiert: Unterarm gemessen, Schulter fest geschätzt. Oberarm %.0f–%.0f cm (Modell %.0f cm).",
                                upper.lowerBound * 100, upper.upperBound * 100, ArmModel.upperArmLength * 100))
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        stat("Handgelenk max.", String(format: "%.0f km/h", swing.peakWristSpeed * 3.6))
                        stat("Jetzt", String(format: "%.0f km/h", current.wristSpeed * 3.6))
                        stat("Unterarm", String(format: "%+.0f°", current.forearmRotationDeg))
                    }
                    RotationChart(swing: swing, currentTime: current.t)
                        .frame(height: 90)
                    Slider(value: $scrub, in: 0...1) { Text("Zeit") }
                    Picker("Handgelenk", selection: $wristSetting) {
                        Text("Auto (\(recording.wrist == .right ? "rechts" : "links"))").tag("auto")
                        Text("Links").tag(Side.left.rawValue)
                        Text("Rechts").tag(Side.right.rawValue)
                    }
                    .pickerStyle(.segmented)
                    SpeedLegend(maxSpeed: swing.peakWristSpeed)
                }
                .padding()
            }
            .navigationTitle("Schwung")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Kein Schwung erkannt", systemImage: "figure.golf",
                                   description: Text("Zu wenige Samples oder keine klare Bewegungsspitze."))
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Unterarmrotation über die Zeit. + = Supination, − = Pronation, 0 = Ansprechen.
struct RotationChart: View {
    let swing: ReconstructedSwing
    let currentTime: Double

    var body: some View {
        Chart {
            ForEach(Array(swing.points.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Zeit", p.t), y: .value("Rotation", p.forearmRotationDeg))
            }
            RuleMark(y: .value("Ansprechen", 0)).foregroundStyle(.secondary.opacity(0.4))
            RuleMark(x: .value("Treffmoment", swing.peakTime))
                .foregroundStyle(.orange.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            RuleMark(x: .value("Jetzt", currentTime)).foregroundStyle(.primary)
        }
        .chartYAxisLabel("Supination + / Pronation − (°)")
        .chartXAxisLabel("s")
    }
}

struct SpeedLegend: View {
    let maxSpeed: Double
    var body: some View {
        HStack {
            Text("0").font(.caption2)
            LinearGradient(colors: (0...4).map { SpeedColor.color(Double($0) / 4) }, startPoint: .leading, endPoint: .trailing)
                .frame(height: 8).clipShape(Capsule())
            Text("\(maxSpeed * 3.6, specifier: "%.0f") km/h").font(.caption2)
        }
    }
}

enum SpeedColor {
    /// 0 → blau, 1 → rot
    static func hue(_ f: Double) -> Double { 0.66 * (1 - min(max(f, 0), 1)) }
    static func color(_ f: Double) -> Color { Color(hue: hue(f), saturation: 0.9, brightness: 1) }
    static func rgba(_ f: Double) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hue: hue(f), saturation: 0.9, brightness: 1, alpha: 1).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), 1)
    }
}
