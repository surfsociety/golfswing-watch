import Foundation
import WatchConnectivity

final class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()
    private weak var store: SwingStore?

    func activate(store: SwingStore) {
        self.store = store
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Die Datei wird nach Rückkehr dieser Methode gelöscht, daher synchron lesen.
        guard let data = try? Data(contentsOf: file.fileURL),
              let recording = try? JSONDecoder().decode(SwingRecording.self, from: data) else { return }
        Task { @MainActor in self.store?.add(recording) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
