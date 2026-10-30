import Foundation

/// Hält alle Aufnahmen und persistiert sie als JSON in Documents/swings.
@MainActor
final class SwingStore: ObservableObject {
    @Published private(set) var recordings: [SwingRecording] = []

    private let folder: URL = {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("swings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init() { load() }

    func add(_ recording: SwingRecording) {
        recordings.insert(recording, at: 0)
        if let data = try? JSONEncoder().encode(recording) {
            try? data.write(to: folder.appendingPathComponent("\(recording.id.uuidString).json"))
        }
    }

    func delete(at offsets: IndexSet) {
        for i in offsets {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(recordings[i].id.uuidString).json"))
        }
        recordings.remove(atOffsets: offsets)
    }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        recordings = files
            .compactMap { try? JSONDecoder().decode(SwingRecording.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }
}
