import Foundation
import CoreLocation
import Combine

/// Simplified permission state the UI can act on.
enum LocationAccess: Equatable {
    case notDetermined, granted, denied, restricted
}

/// Thin wrapper around CLLocationManager. Publishes the latest fix and keeps
/// updating in the background (blue bar) while a pass is recording.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var access: LocationAccess = .notDetermined
    /// Last non-fatal error worth showing (e.g. "location unavailable").
    @Published private(set) var lastErrorMessage: String?

    private let manager = CLLocationManager()
    private var wantsUpdates = false

    /// Fixes worse than this are ignored (indoor / cold-start garbage).
    private let maxUsableAccuracy: CLLocationAccuracy = 200
    /// Fixes older than this are cached positions, not live ones.
    private let maxFixAge: TimeInterval = 15

    /// True only if the app is actually configured for the `location` background
    /// mode. Setting `allowsBackgroundLocationUpdates` without it throws, so we guard.
    private var backgroundModeEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?
            .contains("location") ?? false
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        refreshAccess()
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        refreshAccess()
    }

    func startUpdating() {
        wantsUpdates = true
        location = nil
        lastErrorMessage = nil
        configureBackground()
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        wantsUpdates = false
        if backgroundModeEnabled { manager.allowsBackgroundLocationUpdates = false }
        manager.stopUpdatingLocation()
    }

    private var isAuthorized: Bool {
        let s = manager.authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    private func configureBackground() {
        // Background updates require UIBackgroundModes "location" (set in build settings).
        if backgroundModeEnabled, isAuthorized {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
    }

    // `CLLocationManager.locationServicesEnabled()` blocks the main thread on
    // iOS 16+, so "services off" is reported through `.denied` instead.
    private func refreshAccess() {
        switch manager.authorizationStatus {
        case .notDetermined: access = .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: access = .granted
        case .denied: access = .denied
        case .restricted: access = .restricted
        @unknown default: access = .denied
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshAccess()
        if wantsUpdates, isAuthorized {
            configureBackground()
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last(where: { fix in
            fix.horizontalAccuracy >= 0
                && fix.horizontalAccuracy <= maxUsableAccuracy
                && abs(fix.timestamp.timeIntervalSinceNow) <= maxFixAge
                && CLLocationCoordinate2DIsValid(fix.coordinate)
        }) else { return }
        lastErrorMessage = nil
        location = loc
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let clError = error as? CLError else { return }
        switch clError.code {
        case .denied:
            refreshAccess()
            lastErrorMessage = "Location access was turned off."
        case .locationUnknown:
            // Transient: GPS hasn't got a fix yet. Keep trying silently.
            break
        default:
            lastErrorMessage = "GPS error: \(clError.localizedDescription)"
        }
    }
}
