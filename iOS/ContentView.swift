import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: SwingStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Demo-Schwung erzeugen") { store.add(DemoSwing.make()) }
                } footer: {
                    Text("Auf der Watch „Start“ tippen, schwingen, im Finish kurz stillhalten, „Stopp & senden“.")
                }
                Section("Aufnahmen") {
                    ForEach(store.recordings) { rec in
                        NavigationLink {
                            SwingDetailView(recording: rec)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(rec.date.formatted(date: .abbreviated, time: .standard))
                                Text("\(rec.samples.count) Samples · \(rec.source)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: store.delete)
                }
            }
            .navigationTitle("Golf Swing")
        }
    }
}
