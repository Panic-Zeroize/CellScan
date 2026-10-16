import SwiftUI
import CoreLocation

// UI-only extensions for the Foundation-only model in Core/.

extension Carrier {
    var color: Color {
        switch self {
        case .verizon: return Color(hex: 0xEE2A2A)
        case .att: return Color(hex: 0x00A8E0)
        case .tmobile: return Color(hex: 0xE20074)
        case .other: return Color(hex: 0x6B7280)
        }
    }
}

extension RAT {
    var color: Color {
        switch self {
        case .fiveG: return Color(hex: 0x34D399)
        case .lte: return Color(hex: 0x38BDF8)
        case .threeG: return Color(hex: 0xFBBF24)
        case .twoG: return Color(hex: 0xFB923C)
        case .none: return Color(hex: 0xF43F5E)
        }
    }
}

extension CoverageTier {
    var color: Color {
        switch self {
        case .great: return Color(hex: 0x34D399)
        case .good: return Color(hex: 0x38BDF8)
        case .ok: return Color(hex: 0xFBBF24)
        case .poor: return Color(hex: 0xFB923C)
        case .dead: return Color(hex: 0xF43F5E)
        }
    }
}

extension Pass {
    /// Color for the pass's dot: its carrier, or neutral for a mixed combine.
    var carrierColor: Color { carriers.count == 1 ? carriers[0].color : Carrier.other.color }
}

extension Sample {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

extension Cell {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

enum RelativeDate {
    /// "Today · 3:41 PM", "Yesterday · …", "Tue · …" within a week, else "Oct 3 · …".
    static func string(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date) { return "Today · \(time)" }
        if cal.isDateInYesterday(date) { return "Yesterday · \(time)" }
        if let days = cal.dateComponents([.day], from: date, to: now).day, days >= 0, days < 7 {
            return "\(date.formatted(.dateTime.weekday(.abbreviated))) · \(time)"
        }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())) · \(time)"
    }

    static func short(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
