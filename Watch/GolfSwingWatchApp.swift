import SwiftUI

@main
struct GolfSwingWatchApp: App {
    @StateObject private var recorder = SwingRecorder()

    init() {
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(recorder)
                .task { await recorder.requestAuthorization() }
        }
    }
}
