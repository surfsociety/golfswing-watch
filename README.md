# Golf Swing – Apple Watch + iPhone

Die Watch zeichnet den Schwung mit 200 Hz auf, das iPhone rekonstruiert daraus die 3D-Bahn des Handgelenks und färbt sie nach Geschwindigkeit ein.

## Öffnen in Xcode (Mac nötig)

1. XcodeGen installieren: `brew install xcodegen`
2. In diesem Ordner: `xcodegen generate` → erzeugt `GolfSwing.xcodeproj`
3. Projekt öffnen, bei beiden Targets unter *Signing & Capabilities* dein Team wählen und die Bundle-IDs `com.example.golfswing…` auf eine eigene Domain ändern (beide Targets konsistent, inkl. `WKCompanionAppBundleIdentifier` in `project.yml`).
4. Scheme **GolfSwing** auf das gekoppelte iPhone ausführen; die Watch-App wird mitinstalliert. Ohne Watch: im Simulator „Demo-Schwung erzeugen“.

Voraussetzungen: Xcode 15+, iOS 17, watchOS 10. 200 Hz über `CMBatchedSensorManager` nur auf Series 8+ und Ultra; ältere Watches fallen automatisch auf 100 Hz zurück.

## Bedienung

Watch: **Start** → mindestens 0,5 s ruhig ansprechen → schwingen → **im Finish ~0,5 s stillhalten** → **Stopp & senden**. Die Ruhephasen sind keine Kosmetik: Sie sind die Randbedingung (v = 0), mit der die Integrationsdrift entfernt wird.

## Architektur

| Datei | Aufgabe |
|---|---|
| `Watch/SwingRecorder.swift` | HKWorkoutSession (Golf) + `CMBatchedSensorManager.deviceMotionUpdates()` (200 Hz), Fallback `CMMotionManager` 100 Hz |
| `Watch/WatchSessionManager.swift` | Übertragung per `WCSession.transferFile` (JSON) |
| `Shared/SwingModels.swift` | Rohdaten: Attitude-Quaternion, userAcceleration, rotationRate |
| `iOS/SwingReconstructor.swift` | Segmentierung → Drehung ins Weltsystem → doppelte Integration mit Drift-Korrektur |
| `iOS/SwingSceneView.swift` | SceneKit: Achsen (1 m), Gitter, Bahn nach Speed eingefärbt, Zeit-Marker |
| `iOS/DemoSwing.swift` | Synthetischer Schwung mit bekannter Wahrheit (Test ohne Watch) |
| `Tools/verify_reconstruction.py` | Gleiche Mathematik in Python, prüft Fehler gegen die Wahrheit |

## Was die Zahlen bedeuten (und was nicht)

- **Bahn:** Handgelenk, nicht Schlägerkopf. Relativ zur Ansprechposition. Z/blau = vertikal, X-Richtung ist beliebig (kein Kompass), also *nicht* automatisch die Ziellinie.
- **Handgelenk-Speed:** aus der integrierten Geschwindigkeit.
- **Nur Handgelenk:** Die Ansicht zeigt bewusst nur die Bahn und das Tempo des Handgelenks, an dem die Watch sitzt. Der Rekonstruktor berechnet intern weiter eine grobe Schlägerkopf-Schätzung (|ω| × Hebel); sie wird nicht angezeigt.

## Verifikation der Rekonstruktion (Python, Ergebnis)

`python3 Tools/verify_reconstruction.py` mit dem Demo-Schwung (Kreis r = 0,7 m, 60°-Ebene):

| Szenario | max. Positionsfehler |
|---|---|
| 200 Hz, ideal | 0,2 cm |
| 100 Hz, ideal | 0,8 cm |
| 200 Hz, Rauschen 0,02 g | 2,7 cm |
| konstanter Bias 0,03 g | 0,2 cm (Drift-Korrektur entfernt ihn vollständig) |
| 2° Attitude-Fehler im Abschwung | 5,6 cm |
| 5° Attitude-Fehler im Abschwung | 13,7 cm |

Kernaussage: Der dominante Fehler auf echter Hardware ist nicht Rauschen, sondern die **Attitude-Genauigkeit während des Abschwungs**. Das ist das Erste, was am echten Gerät zu prüfen ist.

## Offene Risiken auf echter Hardware

1. **Gyro-Sättigung:** Das Handgelenk erreicht im Abschwung Winkelgeschwindigkeiten im Bereich von ~1.500–2.500 °/s; Apple veröffentlicht den Messbereich des Watch-Gyros nicht. Clippt er, kippt die Attitude → Gravitationsleck → Bahnfehler. Prüfen: `rotationRate`-Verlauf auf abgeflachte Spitzen ansehen.
2. **XcodeGen + Watch-App mit einem Target:** Sollte mit aktuellem XcodeGen funktionieren, ist aber ohne Mac hier nicht gebaut. Falls das Embedding hakt: In Xcode ein neues iOS-App-Projekt mit „Watch App“ anlegen und die Swift-Dateien hineinziehen.
3. **Segmentierung:** Waggles vor dem Schwung oder fehlende Ruhe im Finish brechen die Randbedingung. Die App warnt dann.
