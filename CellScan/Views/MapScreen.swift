import SwiftUI
import MapKit

struct MapScreen: View {
    var pass: Pass
    @Environment(\.dismiss) private var dismiss

    enum Mode { case rat, throughput }
    @State private var mode: Mode = .throughput   // per user's choice: color by real speed
    @State private var selected: Cell?
    @State private var position: MapCameraPosition

    private let cells: [Cell]

    init(pass: Pass) {
        self.pass = pass
        self.cells = pass.cells
        _position = State(initialValue: .region(Self.region(for: pass.cells)))
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            mapLayer
            topOverlay
            modeSwitch
            legend
            if let sel = selected { detailSheet(sel) }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $position) {
            if cells.count > 1 {
                MapPolyline(coordinates: cells.map { $0.coordinate })
                    .stroke(Theme.accent.opacity(0.5), lineWidth: 3)
            }
            ForEach(cells) { cell in
                Annotation("", coordinate: cell.coordinate) {
                    cellDot(cell)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .ignoresSafeArea()
    }

    private func cellDot(_ cell: Cell) -> some View {
        let col = color(for: cell)
        let isSel = selected?.id == cell.id
        let size = min(26, 12 + CGFloat(cell.sampleCount - 1) * 1.5)
        return Circle()
            .fill(col.opacity(0.32))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(isSel ? Color.white : col, lineWidth: isSel ? 2 : 1.5))
            .shadow(color: col.opacity(0.6), radius: isSel ? 8 : 4)
            .onTapGesture { withAnimation { selected = cell } }
    }

    // MARK: - Overlays

    private var topOverlay: some View {
        VStack {
            HStack {
                glassButton { dismiss() } content: {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                }
                Spacer()
                VStack(spacing: 1) {
                    Text("\(pass.carrier.displayName) · \(RelativeDate.short(pass.startedAt))")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(cells.count) cells · tap for detail")
                        .font(.system(size: 10.5)).foregroundStyle(Color(hex: 0x8A929B))
                }
                .padding(.vertical, 7).padding(.horizontal, 16)
                .background(glass)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                Spacer()
                Color.clear.frame(width: 38, height: 38)
            }
            .padding(.horizontal, 16)
            Spacer()
        }
    }

    private var modeSwitch: some View {
        VStack {
            HStack(spacing: 3) {
                segButton("Color: RAT", active: mode == .rat) { mode = .rat }
                segButton("Throughput", active: mode == .throughput) { mode = .throughput }
            }
            .padding(3)
            .background(glass)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .padding(.top, 62)
            Spacer()
        }
    }

    private var legend: some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(mode == .rat ? "RAT TIER" : "DOWNLOAD")
                        .font(.system(size: 10, weight: .semibold)).tracking(1)
                        .foregroundStyle(Theme.textFaint)
                    ForEach(legendItems, id: \.label) { item in
                        HStack(spacing: 8) {
                            Circle().fill(item.color).frame(width: 11, height: 11)
                                .shadow(color: item.color.opacity(0.7), radius: 3)
                            Text(item.label).font(.system(size: 11.5))
                                .foregroundStyle(Color(hex: 0xC7CDD3))
                        }
                    }
                }
                .padding(.vertical, 11).padding(.horizontal, 13)
                .background(glass)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, selected == nil ? 34 : 300)
        }
    }

    private func detailSheet(_ cell: Cell) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 38, height: 5)
                    .padding(.top, 10).padding(.bottom, 14)
                HStack {
                    SignalBadge(rat: cell.rat)
                    Spacer()
                    Button { withAnimation { selected = nil } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(hex: 0x9AA3AD))
                            .frame(width: 30, height: 30)
                            .background(Color(hex: 0x1E222A)).clipShape(Circle())
                    }
                }
                HStack {
                    Text(String(format: "%.5f, %.5f", cell.lat, cell.lng))
                    Spacer()
                    Text(cell.time.formatted(date: .omitted, time: .standard))
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .padding(.top, 11)
                Text("Worst of \(cell.sampleCount) sample\(cell.sampleCount == 1 ? "" : "s") merged into this cell")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 5)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    detailTile("LATENCY", cell.latencyMs.map { String(format: "%.0f ms", $0) } ?? "timeout")
                    detailTile("DOWN", cell.downMbps.map { String(format: "%.0f Mb", $0) } ?? "—")
                    detailTile("UP", cell.upMbps.map { String(format: "%.1f Mb", $0) } ?? "—")
                    detailTile("±ACC", String(format: "%.0f m", cell.accuracy))
                    detailTile("SPEED", String(format: "%.0f mph", cell.speedMph))
                    detailTile("SAMPLES", "\(cell.sampleCount)")
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 20).padding(.bottom, 26)
            .background(Color(hex: 0x101216).opacity(0.97))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .transition(.move(edge: .bottom))
        .ignoresSafeArea(edges: .bottom)
    }

    private func detailTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9)).tracking(0.5).foregroundStyle(Theme.textFaint)
            Text(value).font(.system(size: 15, design: .monospaced)).foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9).padding(.horizontal, 11)
        .background(Color(hex: 0x171B21))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: - Helpers

    private var glass: some ShapeStyle { Color(hex: 0x121419).opacity(0.82) }

    private func glassButton<C: View>(action: @escaping () -> Void, @ViewBuilder content: () -> C) -> some View {
        Button(action: action) {
            content()
                .foregroundStyle(Theme.textBright)
                .frame(width: 38, height: 38)
                .background(glass)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        }
    }

    private func segButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(active ? .white : Color(hex: 0x9AA3AD))
                .padding(.vertical, 7).padding(.horizontal, 13)
                .background(active ? Theme.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func color(for cell: Cell) -> Color {
        mode == .rat ? cell.rat.color : cell.coverage.color
    }

    private var legendItems: [(color: Color, label: String)] {
        if mode == .rat {
            return [(RAT.fiveG.color, "5G"), (RAT.lte.color, "LTE"),
                    (RAT.threeG.color, "3G"), (RAT.none.color, "No service")]
        } else {
            return [(CoverageTier.great.color, "> 120 Mbps"), (CoverageTier.good.color, "30–120"),
                    (CoverageTier.ok.color, "5–30"), (CoverageTier.dead.color, "No data")]
        }
    }

    private static func region(for cells: [Cell]) -> MKCoordinateRegion {
        guard let first = cells.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        var minLat = first.lat, maxLat = first.lat, minLng = first.lng, maxLng = first.lng
        for c in cells {
            minLat = min(minLat, c.lat); maxLat = max(maxLat, c.lat)
            minLng = min(minLng, c.lng); maxLng = max(maxLng, c.lng)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.008, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.008, (maxLng - minLng) * 1.5))
        return MKCoordinateRegion(center: center, span: span)
    }
}

extension RelativeDate {
    static func short(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month().day())
    }
}
