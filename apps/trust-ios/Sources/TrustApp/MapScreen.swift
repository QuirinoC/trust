import MapKit
import SwiftUI
import TrustCore

/// D2 Map — secondary push from View. Pins follow the same Plus gating as home.
/// Sealed people are never on the map. Regular width: full-bleed map + trailing panel.
struct MapScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedID: UUID?

    private var pins: [AppModel.MapPin] { model.homeMapPins }
    private var sealedCount: Int { max(0, model.circle.count - pins.count) }
    private var selected: AppModel.MapPin? {
        pins.first { $0.id == selectedID } ?? pins.first
    }

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= 760
            Group {
                if pins.isEmpty {
                    TrustEmptyState(
                        glyph: "lock",
                        title: TrustCopy.noLocationsYet,
                        message: TrustCopy.mapEmptyBody,
                        actionTitle: TrustCopy.backToCircle
                    ) {
                        model.circlePath = []
                    }
                } else if isWide {
                    regularContent
                } else {
                    compactContent
                }
            }
        }
        .background(palette.paper.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(palette.paper, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.circlePath = []
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                        Text(TrustCopy.people)
                    }
                    .trustFont(15, weight: .medium)
                    .foregroundStyle(palette.ink)
                }
                .accessibilityLabel(TrustCopy.backToCircle)
                .accessibilityIdentifier("map-back-to-people")
            }
        }
        .onAppear {
            model.prepareMapLocation()
            fitAll()
        }
        .onChange(of: pins.map(\.id)) { _, _ in fitAll() }
    }

    /// iPad regular width: full-bleed map + trailing person panel. Compact (iPhone and
    /// Split View / Stage Manager narrow) stays stacked.
    private var regularContent: some View {
        HStack(spacing: 0) {
            mapCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            palette.line.frame(width: 1)
            personPanel(isWide: true)
                .frame(width: 360)
                .background(palette.paper)
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            mapHeader
                .padding(.horizontal, TrustTheme.gutter)
                .padding(.top, 4)
                .padding(.bottom, 12)
            mapCanvas
                .frame(minHeight: 260, maxHeight: .infinity)
            personPanel(isWide: false)
        }
        .padding(.bottom, 16)
    }

    private var mapHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            TrustPageTitle(text: TrustCopy.map)
            Text(TrustCopy.onMap(count: pins.count, sealed: sealedCount))
                .trustFont(12)
                .foregroundStyle(palette.muted)
        }
    }

    private var mapCanvas: some View {
        Map(position: $position, selection: $selectedID) {
            ForEach(pins) { pin in
                Annotation(pin.name, coordinate: pin.point.coordinate) {
                    TrustMapPin(initials: pin.name.trustInitials, live: pin.live, selected: selected?.id == pin.id)
                        .onTapGesture { selectedID = pin.id }
                        .accessibilityLabel(TrustCopy.pinAccessibility(name: pin.name, live: pin.live))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(selected?.id == pin.id ? [.isSelected] : [])
                }
                .tag(pin.id)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .accessibilityLabel(TrustCopy.mapAccessibility)
        .accessibilityIdentifier("map-screen-canvas")
    }

    private func personPanel(isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isWide {
                mapHeader
                    .padding(.horizontal, TrustTheme.gutter)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
            }
            HStack(spacing: 14) {
                if pins.contains(where: \.live) { mapLegend(color: palette.pinLive, title: TrustCopy.always) }
                if pins.contains(where: { !$0.live }) { mapLegend(color: palette.pinLook, title: TrustCopy.snapshot) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, TrustTheme.gutter)
            .padding(.vertical, 10)

            if let selected, let member = model.member(selected.id) {
                personCard(selected, member)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pins) { pin in
                        Button(pin.name.trustFirstName) { selectedID = pin.id }
                            .trustFont(13, weight: .medium)
                            .foregroundStyle(selected?.id == pin.id ? palette.paper : palette.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(selected?.id == pin.id ? palette.ink : palette.surface))
                            .accessibilityLabel(TrustCopy.showOnMap(name: pin.name))
                            .accessibilityAddTraits(selected?.id == pin.id ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, TrustTheme.gutter)
            }
            .padding(.bottom, 12)

            if let selected {
                Button {
                    if let member = model.member(selected.id) { model.openView(member) }
                } label: {
                    HStack(spacing: 6) {
                        Text(TrustCopy.viewLocation(name: selected.name.trustFirstName))
                        Image(systemName: "arrow.right")
                            .trustFont(12, weight: .semibold)
                    }
                }
                .buttonStyle(TrustOutlineButtonStyle(compact: true))
                .padding(.horizontal, TrustTheme.gutter)
            }

            if sealedCount > 0 {
                TrustFootnote(glyph: "lock", text: TrustCopy.sealedNotOnMap(sealedCount))
                    .padding(.horizontal, TrustTheme.gutter)
                    .padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map-screen-person-panel")
    }

    private func personCard(_ pin: AppModel.MapPin, _ member: TrustedPerson) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                TrustAvatar(name: member.person.displayName, seed: model.circle.firstIndex { $0.id == member.id } ?? 0, size: 40, avatar: member.person.avatar, personID: member.id)
                VStack(alignment: .leading, spacing: 4) {
                    Text(member.person.displayName)
                        .trustFont(15, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    Text(subtitle(pin, member))
                        .trustFont(12)
                        .foregroundStyle(palette.muted)
                }
                Spacer()
                TrustBadge(glyph: pin.live ? "eye" : "lock", text: pin.live ? TrustCopy.always : TrustCopy.oneLook)
            }
        }
        .padding(.horizontal, TrustTheme.gutter)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    private func mapLegend(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).trustFont(11, weight: .medium).foregroundStyle(palette.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ pin: AppModel.MapPin, _ member: TrustedPerson) -> String {
        let presence = member.visiblePresence?.label ?? TrustCopy.presenceHiddenBadge
        let time = pin.point.timestamp.formatted(date: .omitted, time: .shortened)
        return "\(presence) · \(pin.live ? TrustCopy.updatedAt(time) : TrustCopy.snapshot)"
    }

    private func fitAll() {
        let coordinates = pins.map(\.point.coordinate)
        guard let first = coordinates.first else { return }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: min(170, max((maxLat - minLat) * 1.4, 0.05)),
            longitudeDelta: min(340, max((maxLon - minLon) * 1.4, 0.05))
        )
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}
