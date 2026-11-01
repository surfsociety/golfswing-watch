import SwiftUI
import Charts

struct SwingDetailView: View {
    let recording: SwingRecording
    /// "auto" = aus den Watch-Einstellungen der Aufnahme, sonst "left"/"right"
    @AppStorage("wristSetting") private var wristSetting = "auto"
    @AppStorage("golferRightHanded") private var golferRightHanded = true
    @AppStorage("grip") private var gripRaw = GripStyle.neutral.rawValue
    @AppStorage("shaftAngleDeg") private var shaftAngleDeg = 30.0
    @State private var scrub = 1.0

    private var handPose: HandPose {
        HandPose(golferRightHanded: golferRightHanded,
                 grip: GripStyle(rawValue: gripRaw) ?? .neutral,
                 shaftAngleDeg: shaftAngleDeg)
    }

    private var swing: ReconstructedSwing? {
        SwingReconstructor.reconstruct(recording, wristOverride: Side(rawValue: wristSetting))
    }

    var body: some View {
        if let swing {
            let current = swing.points[Int((Double(swing.points.count - 1) * scrub).rounded())]
            VStack(spacing: 0) {
                SwingSceneView(swing: swing, progress: scrub, handPose: handPose)
                    .ignoresSafeArea(edges: .horizontal)
                VStack(alignment: .leading, spacing: 8) {
                    if !swing.restDetectedAtBothEnds {
                        Label("Keine Ruhephase vor/nach dem Schwung erkannt – Bahn ist unzuverlässig.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
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
                    DisclosureGroup("Handhaltung beim Ansprechen") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Spielhand", selection: $golferRightHanded) {
                                Text("Rechtshänder").tag(true)
                                Text("Linkshänder").tag(false)
                            }
                            .pickerStyle(.segmented)
                            Picker("Griff", selection: $gripRaw) {
                                ForEach(GripStyle.allCases) { Text($0.label).tag($0.rawValue) }
                            }
                            .pickerStyle(.segmented)
                            Stepper("Winkel Unterarm–Schaft: \(shaftAngleDeg, specifier: "%.0f")°",
                                    value: $shaftAngleDeg, in: 0...60, step: 5)
                            Text(String(format: "Uhr an der %@. Eindrehung beim Ansprechen: %+.0f° (Handrücken + nach oben). Unterarm %.0f° gegen die Senkrechte%@.",
                                        handPose.watchOnLeadHand(wrist: swing.wrist) ? "Führungshand" : "hinteren Hand",
                                        swing.addressRollDeg, swing.addressForearmTiltDeg,
                                        swing.addressForearmTiltDeg < 20 ? " – zu steil, Wert unzuverlässig" : ""))
                                .font(.caption2).foregroundStyle(.secondary)
                            Text("Griff wird gewählt, nicht erkannt. Die Hand ist starr in der Ansprech-Pose am Unterarm befestigt; Beugen und Strecken des Handgelenks misst die Uhr nicht.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    SpeedLegend(maxSpeed: swing.peakWristSpeed)
                }
                .padding()
            }
            .navigationTitle("Schwung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Rohdaten als JSON teilen, z. B. für die Auswertung der Griff-Kalibrierung
                if let url = exportURL() {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            }
        } else {
            ContentUnavailableView("Kein Schwung erkannt", systemImage: "figure.golf",
                                   description: Text("Zu wenige Samples oder keine klare Bewegungsspitze."))
        }
    }

    private func exportURL() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swing-\(recording.date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")).json")
        guard let data = try? JSONEncoder().encode(recording), (try? data.write(to: url)) != nil else { return nil }
        return url
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
