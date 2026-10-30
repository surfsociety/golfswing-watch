import SwiftUI

struct SwingDetailView: View {
    let recording: SwingRecording
    @State private var scrub = 1.0

    private var swing: ReconstructedSwing? {
        SwingReconstructor.reconstruct(recording)
    }

    var body: some View {
        if let swing {
            VStack(spacing: 0) {
                SwingSceneView(swing: swing, progress: scrub)
                    .ignoresSafeArea(edges: .horizontal)
                VStack(alignment: .leading, spacing: 8) {
                    if !swing.restDetectedAtBothEnds {
                        Label("Keine Ruhephase vor/nach dem Schwung erkannt – Bahn ist unzuverlässig.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    stat("Handgelenk max.", swing.peakWristSpeed)
                    Slider(value: $scrub, in: 0...1) { Text("Zeit") }
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

    private func stat(_ title: String, _ mps: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(mps * 3.6, specifier: "%.0f") km/h").font(.title3.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
