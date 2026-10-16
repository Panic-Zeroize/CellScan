import SwiftUI
import MapKit

struct MapScreen: View {
    var passes: [Pass]
    var title: String
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    enum Mode { case rat, throughput }
    @State private var mode: Mode = .throughput   // color by real speed by default
    @State private var didPickMode = false
    @State private var selected: Cell?
    @State private var position: MapCameraPosition
    @State private var enabledLayers: Set<Carrier>
    /// Cached per-carrier cells; rebuilt only when the passes or settings change,
    /// not on every redraw (tapping a cell used to re-merge the whole route).
    @State private var layers: [Layer] = []

    struct Layer: Identifiable {
        var carrier: Carrier
        var cells: [Cell]
        /// Route line split wherever consecutive cells are > 5 min apart, so
        /// separate drives aren't joined by a straight line across the map.
        var segments: [[CLLocationCoordinate2D]]
        var id: Carrier { carrier }
    }

    init(passes: [Pass], title: String) {
        self.passes = passes
        self.title = title
        _position = State(initialValue: .region(Self.region(for: passes)))
        _enabledLayers = State(initialValue: Set(passes.flatMap(\.carriers)))
    }

    // MARK: - Derived data

    private var visibleLayers: [Layer] { layers.filter { enabledLayers.contains($0.carrier) } }

    struct RouteLine: Identifiable {
        var id: String
        var carrier: Carrier
        var coordinates: [CLLocationCoordinate2D]
    }

    /// Every visible route segment as one flat list (one ForEach in the map).
    private var routeLines: [RouteLine] {
        visibleLayers.flatMap { layer in
            layer.segments.enumerated().map { idx, coords in
                RouteLine(id: "\(layer.carrier.rawValue)-\(idx)", carrier: layer.carrier, coordinates: coords)
            }
        }
    }

    /// Changes when the passes shown here change (e.g. after a combine/delete).
    private var passesSignature: String {
        passes.map { "\($0.id.uuidString):\($0.samples.count)" }.joined(separator: ",")
    }
    private var cells: [Cell] { visibleLayers.flatMap(\.cells) }
    private var carriers: [Carrier] { layers.map(\.carrier) }

    private func rebuildLayers() {
        let s = settingsStore.settings
        let previousCarriers = Set(layers.map(\.carrier))
        // Several passes are merged first so co-located samples share one cell
        // (and one id) instead of producing duplicate cells per pass.
        let source = passes.count == 1 ? passes[0] : Pass.combining(passes)
        var byCarrier: [Carrier: [Cell]] = [:]
        var order: [Carrier] = []
        for cell in source.mergedCells(gridMeters: s.cellMergeMeters, average: s.averageCells) {
            if byCarrier[cell.carrier] == nil { order.append(cell.carrier) }
            byCarrier[cell.carrier, default: []].append(cell)
        }
        // Carriers that just appeared start visible.
        enabledLayers.formUnion(Set(order).subtracting(previousCarriers))
        layers = order.map { carrier in
            let cells = (byCarrier[carrier] ?? []).sorted { $0.time < $1.time }
            var segments: [[CLLocationCoordinate2D]] = []
            var current: [CLLocationCoordinate2D] = []
            var lastTime: Date?
            for cell in cells {
                if let t = lastTime, cell.time.timeIntervalSince(t) > 300 {
                    if current.count > 1 { segments.append(current) }
                    current = []
                }
                current.append(cell.coordinate)
                lastTime = cell.time
            }
            if current.count > 1 { segments.append(current) }
            return Layer(carrier: carrier, cells: cells, segments: segments)
        }
        // Keep the detail card in sync with the rebuilt cells.
        if let sel = selected {
            selected = layers.flatMap { $0.cells }.first(where: { $0.id == sel.id })
        }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            mapLayer
            topOverlay
            modeSwitch
            layerChips
            legend
            if !layers.isEmpty && cells.isEmpty { emptyOverlay }
            if let sel = selected { detailSheet(sel) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            rebuildLayers()
            // Passes recorded with the speed test off have no throughput data —
            // coloring them by throughput would paint the whole route "No data" red.
            if !didPickMode {
                didPickMode = true
                if !layers.contains(where: { $0.cells.contains { $0.downMbps != nil } }) { mode = .rat }
            }
        }
        .onChange(of: settingsStore.settings) { _, _ in rebuildLayers() }
        .onChange(of: passesSignature) { _, _ in rebuildLayers() }
    }

    private var emptyOverlay: some View {
        Text("All layers are hidden — tap a carrier to show it.")
            .font(.system(size: 13))
            .foregroundStyle(Theme.textDim)
            .padding(.vertical, 10).padding(.horizontal, 14)
            .background(glass)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $position) {
            ForEach(routeLines) { line in
                MapPolyline(coordinates: line.coordinates)
                    .stroke(line.carrier.color.opacity(0.45), lineWidth: 2.5)
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
            .frame(width: 30, height: 30)          // comfortable tap target
            .contentShape(Circle())
            .onTapGesture { withAnimation { selected = cell } }
            .accessibilityElement()
            .accessibilityLabel("\(cell.carrier.displayName) \(cell.rat.label), \(cell.downMbps.map { String(format: "%.0f megabits", $0) } ?? "no speed data")")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Overlays

    private var topOverlay: some View {
        VStack {
            HStack {
                glassButton { dismiss() } content: {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier("map.back")
                Spacer()
                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
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

    /// One toggleable chip per carrier layer (matches the design's layer control).
    private var layerChips: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(carriers) { carrier in
                        Button {
                            if enabledLayers.contains(carrier) { enabledLayers.remove(carrier) }
                            else { enabledLayers.insert(carrier) }
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(enabledLayers.contains(carrier) ? carrier.color : Color(hex: 0x3A4048))
                                    .frame(width: 10, height: 10)
                                Text(carrier.displayName).font(.system(size: 12.5))
                                    .foregroundStyle(Color(hex: 0xD7DBDF))
                                if enabledLayers.contains(carrier) {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.success)
                                }
                            }
                            .padding(.vertical, 7).padding(.horizontal, 12)
                            .background(glass)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 112)
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
                    HStack(spacing: 6) {
                        Circle().fill(cell.carrier.color).frame(width: 8, height: 8)
                        Text(cell.carrier.displayName).font(.system(size: 12)).foregroundStyle(Theme.textDim)
                    }
                    Button { withAnimation { selected = nil } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(hex: 0x9AA3AD))
                            .frame(width: 30, height: 30)
                            .background(Color(hex: 0x1E222A)).clipShape(Circle())
                    }
                    .accessibilityLabel("Close detail")
                }
                HStack {
                    Text(String(format: "%.5f, %.5f", cell.lat, cell.lng))
                    Spacer()
                    Text(cell.time.formatted(date: .omitted, time: .standard))
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .padding(.top, 11)
                Text("\(settingsStore.settings.averageCells ? "Average" : "Worst") of \(cell.sampleCount) sample\(cell.sampleCount == 1 ? "" : "s") merged into this cell")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 5)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    detailTile("LATENCY", cell.latencyMs.map { String(format: "%.0f ms", $0) } ?? "timeout")
                    detailTile("DOWN", cell.downMbps.map { String(format: "%.0f Mb", $0) } ?? "—")
                    detailTile("UP", cell.upMbps.map { String(format: "%.1f Mb", $0) } ?? "—")
                    detailTile("±ACC", String(format: "%.0f m", cell.accuracy))
                    detailTile("SPEED", settingsStore.settings.speedString(mph: cell.speedMph))
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
                    (RAT.threeG.color, "3G"), (RAT.twoG.color, "2G"), (RAT.none.color, "No service")]
        } else {
            return [(CoverageTier.great.color, "> 120 Mbps"), (CoverageTier.good.color, "30–120"),
                    (CoverageTier.ok.color, "5–30"), (CoverageTier.poor.color, "< 5"),
                    (CoverageTier.dead.color, "No data")]
        }
    }

    private static func region(for passes: [Pass]) -> MKCoordinateRegion {
        let coords = passes.flatMap { $0.samples.filter(\.hasValidCoordinate).map { ($0.lat, $0.lng) } }
        guard let first = coords.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        var minLat = first.0, maxLat = first.0, minLng = first.1, maxLng = first.1
        for c in coords {
            minLat = min(minLat, c.0); maxLat = max(maxLat, c.0)
            minLng = min(minLng, c.1); maxLng = max(maxLng, c.1)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLng + maxLng) / 2)
        // MapKit rejects spans beyond the globe, so clamp.
        let span = MKCoordinateSpan(
            latitudeDelta: min(170, max(0.008, (maxLat - minLat) * 1.5)),
            longitudeDelta: min(350, max(0.008, (maxLng - minLng) * 1.5)))
        return MKCoordinateRegion(center: center, span: span)
    }
}