import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject var recorder: SwingRecorder

    var body: some View {
        VStack(spacing: 8) {
            Text(recorder.isRecording ? "Aufnahme läuft" : "Golf Swing")
                .font(.headline)
            Text("\(recorder.sampleCount) Samples")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button(recorder.isRecording ? "Stopp & senden" : "Start") {
                recorder.isRecording ? recorder.stop() : recorder.start()
            }
            .tint(recorder.isRecording ? .red : .green)
            Text(recorder.statusText)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
