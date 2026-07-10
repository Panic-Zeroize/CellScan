import Foundation
import CoreTelephony
import Combine

/// Reads the current radio access technology (5G / LTE / 3G ...) via CoreTelephony.
/// The carrier *name* is deprecated on modern iOS, but the radio type is still available.
final class RadioMonitor: ObservableObject {
    @Published private(set) var current: RAT = .none

    private let networkInfo = CTTelephonyNetworkInfo()

    init() {
        refresh()
        networkInfo.serviceCurrentRadioAccessTechnologyDidUpdateNotifier = { [weak self] (_: String) in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    /// Returns the freshest radio bucket, also updating the published value.
    @discardableResult
    func refresh() -> RAT {
        let techByService = networkInfo.serviceCurrentRadioAccessTechnology
        // Pick the "best" active service (a phone may report multiple SIMs).
        let best = techByService?.values
            .map { RAT.from(techString: $0) }
            .max(by: { $0.tier < $1.tier })
        let rat = best ?? .none
        current = rat
        return rat
    }
}
