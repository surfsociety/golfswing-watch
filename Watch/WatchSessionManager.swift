import Foundation
import WatchConnectivity

/// Überträgt Aufnahmen als JSON-Datei. transferFile ist zuverlässiger als sendMessage,
/// weil es auch funktioniert, wenn die iPhone-App gerade nicht im Vordergrund ist.
final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ recording: SwingRecording) throws {
        let data = try JSONEncoder().encode(recording)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swing-\(recording.id.uuidString).json")
        try data.write(to: url)
        WCSession.default.transferFile(url, metadata: ["type": "swing"])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
