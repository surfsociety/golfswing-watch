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

## Handgelenk links/rechts

Standard ist **Auto**: Die Watch schickt mit jeder Aufnahme mit, an welchem Handgelenk sie laut watchOS-Einstellungen sitzt und auf welcher Seite die Krone ist. Im Schwung-Detail lässt sich das per Umschalter (Auto / Links / Rechts) überschreiben; die Wahl bleibt gespeichert. Die Seite bestimmt, welche Geräteachse als Unterarmachse gilt und welches Vorzeichen Supination bekommt. Auf die Bahn selbst hat sie keinen Einfluss.

## Drehung des Handgelenks

- **Band statt Linie:** Die Bahn ist ein Band, dessen Fläche immer zur Uhrenoberseite zeigt. Wo sich das Band verdreht, rotiert der Unterarm.
- **Marker:** Eine ausgerichtete Uhr (Display orange) mit Stab Richtung Ellbogen, gesteuert über den Zeit-Slider.
- **Kurve:** Unterarmrotation seit dem Ansprechen in Grad. **+ = Supination** (Handfläche dreht nach oben), **− = Pronation**. Gestrichelte Linie = Treffmoment (Spitze der Winkelgeschwindigkeit).
- **Berechnung:** Integral der Gyro-Drehrate um die Unterarmachse. Bewusst nicht aus der Attitude zerlegt, weil diese Zerlegung bei ~180° Armschwung (Top des Rückschwungs) instabil wird.

**Grenze:** Die Watch sitzt am Unterarm, nicht auf der Hand. Messbar ist deshalb die **Unterarmrotation** (Pronation/Supination) und die Lage des Unterarms. **Beugen/Strecken und Abwinkeln des Handgelenks** (z. B. „gebeugtes Handgelenk im Top“) sieht die Uhr nicht.

**Kalibrier-Check am Gerät (30 Sekunden):** Arm vor dem Körper ausstrecken, Handfläche nach unten, Aufnahme starten, kurz ruhig halten, Handfläche zügig nach oben drehen, ruhig halten, stoppen. Erwartung: Kurve steigt auf etwa +150 bis +180°. Zeigt sie ins Negative, stimmt die Seite (Links/Rechts) oder die Kronen-Annahme nicht.

## Stilisierter Arm

Am Zeit-Marker hängt ein Arm aus Schulter, Oberarm, Ellbogen, Unterarm, Uhr und Hand.

- **Unterarm: gemessen.** Handgelenk aus der Bahn, Richtung aus der Attitude der Uhr. Ellbogen = Handgelenk − 27 cm entlang der Unterarmachse.
- **Schulter: geschätzt.** Beim Ansprechen in Verlängerung des gestreckten Unterarms (+31 cm), danach **fest im Raum**. Die echte Führungsschulter wandert im Schwung durch die Körperdrehung; das bildet das Modell nicht ab.
- **Oberarm:** Verbindung Schulter–Ellbogen, Länge daher nicht erzwungen. Die App zeigt die Spanne an. Weicht sie stark von 31 cm ab, ist das ein Hinweis auf Schulterbewegung oder Drift, kein Messwert der Armlänge.
- Längen sind Durchschnittswerte (`ArmModel` in `SwingReconstructor.swift`), keine Messung.

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

- **Bahn:** Handgelenk (nur das, an dem die Watch sitzt), nicht Schlägerkopf. Relativ zur Ansprechposition. Z/blau = vertikal, X-Richtung ist beliebig (kein Kompass), also *nicht* automatisch die Ziellinie.
- **Handgelenk-Speed:** aus der integrierten Geschwindigkeit.
- **Nur Handgelenk:** Die Ansicht zeigt bewusst nur die Bahn und das Tempo des Handgelenks, an dem die Watch sitzt. Der Rekonstruktor berechnet intern weiter eine grobe Schlägerkopf-Schätzung (|ω| × Hebel); sie wird nicht angezeigt.

## Verifikation der Rekonstruktion (Python, Ergebnis)

`python3 Tools/verify_reconstruction.py` mit dem Demo-Schwung (60°-Ebene):

Der Demo-Schwung ist ein gestreckter Arm (Schulter im Kreismittelpunkt, r = 58 cm) mit bekannter Unterarmrotation (Top +69° Supination, Finish −74° Pronation, linker Arm).

| Szenario | Bahn | Rotation | Ellbogen | Oberarm-Spanne |
|---|---|---|---|---|
| 200 Hz, ideal | 0,2 cm | 0,6° | 0,2 cm | 31–31 cm |
| 100 Hz, ideal | 0,7 cm | 2,5° | 0,7 cm | 30–31 cm |
| 200 Hz, Rauschen 0,02 g | 1,4 cm | 0,6° | 1,4 cm | 31–32 cm |
| 1° Attitude-Fehler im Abschwung | 2,8 cm | 0,6° | 2,8 cm | 28–33 cm |
| 2° Attitude-Fehler im Abschwung | 5,6 cm | 0,6° | 5,6 cm | 25–36 cm |
| 5° Attitude-Fehler im Abschwung | 13,7 cm | 0,6° | 13,7 cm | 17–43 cm |

Ein konstanter Beschleunigungs-Bias wird von der Drift-Korrektur vollständig entfernt. Gyro-Bias ist im Modell nicht enthalten; bei typischen Werten unter 1 °/s liegt die Rotationsdrift über 2–3 s Schwungdauer im einstelligen Gradbereich (Schätzung).

Kernaussage: Der dominante Fehler auf echter Hardware ist nicht Rauschen, sondern die **Attitude-Genauigkeit während des Abschwungs**. Das ist das Erste, was am echten Gerät zu prüfen ist.

## Offene Risiken auf echter Hardware

1. **Gyro-Sättigung:** Das Handgelenk erreicht im Abschwung Winkelgeschwindigkeiten im Bereich von ~1.500–2.500 °/s; Apple veröffentlicht den Messbereich des Watch-Gyros nicht. Clippt er, kippt die Attitude → Gravitationsleck → Bahnfehler. Prüfen: `rotationRate`-Verlauf auf abgeflachte Spitzen ansehen.
2. **XcodeGen + Watch-App mit einem Target:** Sollte mit aktuellem XcodeGen funktionieren, ist aber ohne Mac hier nicht gebaut. Falls das Embedding hakt: In Xcode ein neues iOS-App-Projekt mit „Watch App“ anlegen und die Swift-Dateien hineinziehen.
3. **Segmentierung:** Waggles vor dem Schwung oder fehlende Ruhe im Finish brechen die Randbedingung. Die App warnt dann.
