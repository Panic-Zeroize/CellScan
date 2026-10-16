import Foundation
import CoreTelephony

/// Reads the current radio access technology (5G / LTE / 3G ...) via CoreTelephony.
/// The carrier *name* is deprecated on modern iOS, but the radio type is still available.
/// CoreTelephony has no reliable push notifier for RAT changes, so the recording
/// engine polls `current()` on every captured sample.
final class RadioMonitor {
    private let networkInfo = CTTelephonyNetworkInfo()

    /// The best radio bucket across active SIMs (`.none` with no service / no SIM).
    func current() -> RAT {
        guard let techByService = networkInfo.serviceCurrentRadioAccessTechnology,
              !techByService.isEmpty else { return .none }
        return techByService.values
            .map { RAT.from(techString: $0) }
            .max(by: { $0.tier < $1.tier }) ?? .none
    }
}
