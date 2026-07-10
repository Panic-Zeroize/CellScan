import Foundation
import CoreLocation
import Combine

/// Thin wrapper around CLLocationManager. Publishes the latest fix and keeps
/// updating in the background (blue bar) while a pass is recording.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var wantsBackground = false

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
        authorization = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        wantsBackground = true
        // Background updates require UIBackgroundModes "location" (set in build settings).
        if backgroundModeEnabled,
           manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        wantsBackground = false
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if wantsBackground,
           manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways {
            if backgroundModeEnabled { manager.allowsBackgroundLocationUpdates = true }
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        location = loc
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal: transient GPS errors are expected while driving.
    }
}
