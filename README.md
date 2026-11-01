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

## Stilisierter Unterarm und Hand im Griff

Am Zeit-Marker hängen Unterarm (27 cm), Uhr und eine Hand im Griff: Handteller, vier Finger um ein angedeutetes Griffstück, Daumen oben auf dem Schaft, gelber Schlagflächen-Marker am Schaftende.

- **Gemessen:** Lage und Drehung des Unterarms (Bahn + Attitude der Uhr).
- **Angenommen (einstellbar unter „Handhaltung beim Ansprechen“):** Spielhand (Standard Rechtshänder, Uhr links = Führungshand), Griff (schwach/neutral/stark, ±25° Drehung der Hand am Schaft, Schätzwert) und Winkel Unterarm–Schaft beim Ansprechen (Standard 30°, Schätzwert).
- Die Hand ist in dieser Ansprech-Pose **starr** am Unterarm befestigt. Beugen, Strecken und Abwinkeln des Handgelenks im Schwung misst die Uhr nicht; die Hand knickt deshalb nie ab, auch nicht im Top.
- Der Griff wird **gewählt, nicht erkannt**. Als Rohwert zeigt die App die **Eindrehung beim Ansprechen**: Drehung des Handrückens gegen die Waagrechte, absolut über die Schwerkraft gemessen (+ = Richtung Himmel). Bei einem Unterarm steiler als 20° gegen die Senkrechte ist der Wert unzuverlässig.

## Griff-Erkennung: Machbarkeit (noch nicht gebaut)

Die Griffstärke ist die Drehung der Hand am Schaft. Die Uhr sieht nur die Eindrehung des Unterarms, und die hängt zusätzlich von der Ansprech-Haltung ab. Ob sich die Griffe trennen lassen, entscheidet daher eine Messung, nicht die Mathematik:

1. Je Griff 10 Ansprech-Positionen aufnehmen, dazwischen jedes Mal loslassen, weggehen, neu greifen. Reihenfolge mischen.
2. Aufnahmen über das Teilen-Symbol als JSON exportieren.
3. Auswertung: Mittelwert und Streuung der Eindrehung je Griff. Erkennung lohnt sich nur, wenn benachbarte Griffe mindestens drei Streuungen auseinanderliegen; Ziel ≥ 90 % richtige Zuordnung in einer zweiten, unabhängigen Sitzung (am besten an einem anderen Tag, Armband neu angelegt).
4. Referenz von außen: je Aufnahme ein Foto von vorn auf die Führungshand (sichtbare Knöchel).

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

Der Demo-Schwung ist ein gestreckter Arm (Kreismittelpunkt = Schulter, r = 58 cm) mit bekannter Unterarmrotation (Top +69° Supination, Finish −74° Pronation, linker Arm).

| Szenario | Bahn | Rotation | Ellbogen-Ende des Unterarms |
|---|---|---|---|
| 200 Hz, ideal | 0,2 cm | 0,6° | 0,2 cm |
| 100 Hz, ideal | 0,7 cm | 2,5° | 0,7 cm |
| 200 Hz, Rauschen 0,02 g | 1,4 cm | 0,6° | 1,4 cm |
| 1° Attitude-Fehler im Abschwung | 2,8 cm | 0,6° | 2,8 cm |
| 2° Attitude-Fehler im Abschwung | 5,6 cm | 0,6° | 5,6 cm |
| 5° Attitude-Fehler im Abschwung | 13,7 cm | 0,6° | 13,7 cm |

Ein konstanter Beschleunigungs-Bias wird von der Drift-Korrektur vollständig entfernt. Gyro-Bias ist im Modell nicht enthalten; bei typischen Werten unter 1 °/s liegt die Rotationsdrift über 2–3 s Schwungdauer im einstelligen Gradbereich (Schätzung).

Kernaussage: Der dominante Fehler auf echter Hardware ist nicht Rauschen, sondern die **Attitude-Genauigkeit während des Abschwungs**. Das ist das Erste, was am echten Gerät zu prüfen ist.

## Offene Risiken auf echter Hardware

1. **Gyro-Sättigung:** Das Handgelenk erreicht im Abschwung Winkelgeschwindigkeiten im Bereich von ~1.500–2.500 °/s; Apple veröffentlicht den Messbereich des Watch-Gyros nicht. Clippt er, kippt die Attitude → Gravitationsleck → Bahnfehler. Prüfen: `rotationRate`-Verlauf auf abgeflachte Spitzen ansehen.
2. **XcodeGen + Watch-App mit einem Target:** Sollte mit aktuellem XcodeGen funktionieren, ist aber ohne Mac hier nicht gebaut. Falls das Embedding hakt: In Xcode ein neues iOS-App-Projekt mit „Watch App“ anlegen und die Swift-Dateien hineinziehen.
3. **Segmentierung:** Waggles vor dem Schwung oder fehlende Ruhe im Finish brechen die Randbedingung. Die App warnt dann.
