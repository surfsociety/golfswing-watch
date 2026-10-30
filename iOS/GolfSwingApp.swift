import SwiftUI

@main
struct GolfSwingApp: App {
    @StateObject private var store = SwingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear { PhoneSessionManager.shared.activate(store: store) }
        }
    }
}
