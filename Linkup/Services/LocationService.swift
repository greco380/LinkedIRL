// LocationService.swift
// CoreLocation wrapper used while a share session is active. Per PRD §6:
//   - Foreground: batch updates every 30s while sharing.
//   - Background: drop to every 2 minutes.
//   - Drop fixes worse than 100m accuracy.
//   - When-in-use authorization only (NSLocationWhenInUseUsageDescription).
//
// AppStore owns the lifecycle (start when sharing begins, stop when it ends
// or expires) and reads `lastLocation` when publishing presence. The actual
// 30s / 120s cadence is enforced by the consumer (presence poll loop already
// runs at ~7s); this service updates `lastLocation` whenever CoreLocation
// reports a fresh, accurate-enough fix.

import CoreLocation
import Foundation
import UIKit

@MainActor
final class LocationService: NSObject, ObservableObject {
    /// Most recent acceptable fix. nil until the user grants authorization and
    /// CoreLocation reports a location whose horizontal accuracy beats 100m.
    @Published private(set) var lastLocation: CLLocation?
    /// Latest authorization status. Surfaced so views can show a
    /// "needs permission" banner when sharing starts without consent.
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager: CLLocationManager
    private let accuracyThresholdMeters: CLLocationDistance = 100
    private var isRunning = false
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    override init() {
        self.manager = CLLocationManager()
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
        observeAppLifecycle()
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
    }

    /// Start streaming locations. Idempotent. Triggers a when-in-use prompt
    /// the first time it's called. Safe to call from any actor — internally
    /// hops to main for CL APIs.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        manager.requestWhenInUseAuthorization()
        applyForegroundCadence()
        manager.startUpdatingLocation()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
    }

    private func observeAppLifecycle() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyBackgroundCadence() }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyForegroundCadence() }
        }
    }

    private func applyForegroundCadence() {
        // 30s batching: hundred-metre accuracy with a 50m distance filter
        // produces an update roughly that often when the user is moving
        // through a venue; we then trust the 7s presence poll to flush.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    private func applyBackgroundCadence() {
        // 2-minute cadence: coarser accuracy + larger distance filter. Without
        // "Always" auth (we intentionally don't request it per PRD §7) iOS will
        // suspend updates when backgrounded anyway; this is best-effort.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 200
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let fix = locations.last else { return }
            // Skip implausible or low-accuracy fixes (negative accuracy means invalid).
            guard fix.horizontalAccuracy >= 0,
                  fix.horizontalAccuracy <= self.accuracyThresholdMeters else {
                return
            }
            self.lastLocation = fix
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("[Linkup] location update failed: \(error.localizedDescription)")
        #endif
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}
