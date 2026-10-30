import Foundation
import CoreMotion
import HealthKit
import WatchKit

/// Zeichnet Device Motion auf: 200 Hz via CMBatchedSensorManager (Series 8+/Ultra, watchOS 10+),
/// sonst 100 Hz via CMMotionManager. Die Batched-API liefert nur während einer aktiven
/// Workout-Session Daten, daher läuft parallel eine HKWorkoutSession (Golf).
@MainActor
final class SwingRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var sampleCount = 0
    @Published var statusText = "Bereit"

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private let batchedManager = CMBatchedSensorManager()
    private let motionManager = CMMotionManager()
    private var recordTask: Task<Void, Never>?

    private var samples: [MotionSample] = []
    private var t0: TimeInterval?
    private var source = ""
    private var sampleRate = 0.0

    func requestAuthorization() async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: [])
        } catch {
            statusText = "HealthKit: \(error.localizedDescription)"
        }
    }

    func start() {
        guard !isRecording else { return }
        samples.removeAll(keepingCapacity: true)
        t0 = nil
        sampleCount = 0
        startWorkout()
        isRecording = true

        if CMBatchedSensorManager.isDeviceMotionSupported {
            source = "batched-200Hz"
            sampleRate = 200
            statusText = "200 Hz – schwingen, dann im Finish kurz stillhalten"
            recordTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await batch in self.batchedManager.deviceMotionUpdates() {
                        self.append(batch)
                    }
                } catch {
                    self.statusText = "Sensorfehler: \(error.localizedDescription)"
                }
            }
        } else if motionManager.isDeviceMotionAvailable {
            source = "motionManager-100Hz"
            sampleRate = 100
            statusText = "100 Hz (Fallback) – Schläger-Peak wird unterschätzt"
            motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                MainActor.assumeIsolated { self.append([motion]) }
            }
        } else {
            statusText = "Keine Device Motion verfügbar"
            isRecording = false
            endWorkout()
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        recordTask?.cancel()
        recordTask = nil
        batchedManager.stopDeviceMotionUpdates()
        motionManager.stopDeviceMotionUpdates()
        endWorkout()

        let device = WKInterfaceDevice.current()
        let recording = SwingRecording(date: Date(), sampleRateHz: sampleRate, source: source, samples: samples,
                                       wrist: device.wristLocation == .left ? .left : .right,
                                       crown: device.crownOrientation == .left ? .left : .right)
        do {
            try WatchSessionManager.shared.send(recording)
            statusText = "\(samples.count) Samples an iPhone übergeben"
        } catch {
            statusText = "Senden fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func append(_ motions: [CMDeviceMotion]) {
        for m in motions {
            if t0 == nil { t0 = m.timestamp }
            let q = m.attitude.quaternion
            let a = m.userAcceleration
            let r = m.rotationRate
            samples.append(MotionSample(
                t: m.timestamp - (t0 ?? m.timestamp),
                qx: q.x, qy: q.y, qz: q.z, qw: q.w,
                ax: a.x, ay: a.y, az: a.z,
                gx: r.x, gy: r.y, gz: r.z))
        }
        sampleCount = samples.count
    }

    private func startWorkout() {
        let config = HKWorkoutConfiguration()
        config.activityType = .golf
        config.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            session.startActivity(with: Date())
            workoutSession = session
        } catch {
            statusText = "Workout-Session: \(error.localizedDescription)"
        }
    }

    private func endWorkout() {
        workoutSession?.end()
        workoutSession = nil
    }
}
