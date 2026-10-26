import CoreLocation
import MapKit
import SwiftUI
import TrustCore

/// D1 View — one person. Snapshot (after a Look) or live (Available). Receipt line names
/// what just happened; the map is muted and secondary.
struct ViewScreen: View {
    let personID: UUID
    /// Pins already visible in the leading People map for a split layout.
    /// Pass an empty list when the map is not on screen.
    let leadingMapPins: [AppModel.MapPin]
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @State private var placeName: PlaceName?
    @State private var position: MapCameraPosition = .automatic
    @State private var geocodedFor: LocationPoint?

    private var member: TrustedPerson? { model.member(personID) }
    private var snapshot: LookSession? { model.openedSnapshot(for: personID) }
    private var isAvailable: Bool { member?.isAvailable ?? false }

    private var point: LocationPoint? {
        if isAvailable { return member?.livePoint }
        return snapshot?.live
    }

    var body: some View {
        Group {
            if let member {
                if point != nil {
                    content(member)
                } else if member.isSealed, snapshot == nil {
                    sealed(member)
                } else if member.isAvailable {
                    TrustEmptyState(glyph: "location.slash", title: TrustCopy.locationUnavailable, message: TrustCopy.noLocationBody, actionTitle: TrustCopy.backToCircle) {
                        model.circlePath = []
                    }
                } else {
                    TrustEmptyState(glyph: "location.slash", title: TrustCopy.noLocationYet, message: TrustCopy.noLocationBody, actionTitle: TrustCopy.backToCircle) {
                        model.circlePath = []
                    }
                }
            } else {
                TrustEmptyState(title: TrustCopy.people, message: TrustCopy.apiError(code: "not_connected", fallback: nil), actionTitle: TrustCopy.backToCircle) {
                    model.circlePath = []
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
                    .font(TrustTheme.ui(15, weight: .medium))
                    .foregroundStyle(palette.ink)
                }
                .accessibilityLabel(TrustCopy.backToCircle)
                .accessibilityIdentifier("circle-back")
            }
        }
        .onAppear { model.prepareMapLocation() }
        .task(id: point) {
            await geocodeIfNeeded()
        }
        .task(id: isAvailable) {
            // Live share: keep the pin honest while the screen is open. Snapshot: nothing to poll.
            guard isAvailable, !model.isDemoMode else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await model.refresh()
            }
        }
    }

    // MARK: Content

    private func content(_ member: TrustedPerson) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    TrustAvatar(name: member.person.displayName, seed: seed, size: 70, avatar: member.person.avatar, personID: member.id)
                    VStack(alignment: .leading, spacing: 7) {
                        TrustPageTitle(text: member.firstName, size: 32)
                        Text(isAvailable ? TrustCopy.liveShare : TrustCopy.oneTimeLook)
                            .trustFont(12)
                            .foregroundStyle(palette.muted)
                        presenceBadge(member)
                        directionSummary(member)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(placeName?.primary ?? (isAvailable ? TrustCopy.location : TrustCopy.snapshot))
                        .font(TrustTheme.display(30))
                        .tracking(-0.8)
                        .foregroundStyle(palette.ink)
                    if let secondary = placeName?.secondary {
                        Text(secondary)
                            .trustFont(16, weight: .medium)
                            .foregroundStyle(palette.muted)
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)

                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(metaLine(at: context.date))
                        .trustFont(13)
                        .foregroundStyle(palette.muted)
                        .accessibilityIdentifier("view-location-freshness")
                }
                .padding(.bottom, 8)

                if let point, !leadingMapShowsCurrentPoint(point) {
                    pinMap(point, name: member.person.displayName)
                        .padding(.bottom, 14)
                }

                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.positive)
                        .accessibilityHidden(true)
                    Text(isAvailable
                        ? TrustCopy.receiptViewLogged(name: member.firstName)
                        : TrustCopy.receiptNotified(name: member.firstName))
                        .foregroundStyle(palette.ink)
                }
                .font(TrustTheme.ui(12, weight: .medium))
                .padding(.bottom, 18)

                Button {
                    model.circlePath = [.map]
                } label: {
                    Label(TrustCopy.circleMap, systemImage: "map")
                }
                .buttonStyle(TrustOutlineButtonStyle(compact: true))
                .accessibilityIdentifier("view-open-map")

                TrustInfoStrip(
                    glyph: isAvailable ? "eye" : "lock",
                    text: isAvailable
                        ? TrustCopy.stripLive
                        : TrustCopy.stripSnapshot
                )
                .padding(.top, 18)

                if model.isDemoMode, !model.isScreenshotLaunch {
                    Text(TrustCopy.demoSimulated)
                        .font(TrustTheme.ui(11))
                        .foregroundStyle(palette.muted)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, TrustTheme.gutter)
            .padding(.bottom, 28)
            .trustReadableWidth()
        }
    }

    private func sealed(_ member: TrustedPerson) -> some View {
        TrustEmptyState(
            glyph: "lock",
            title: TrustCopy.sealedTitle,
            message: TrustCopy.sealedBody(name: member.firstName),
            actionTitle: TrustCopy.lookAt(name: member.firstName)
        ) {
            model.openLook(member)
        }
    }

    @ViewBuilder
    private func presenceBadge(_ member: TrustedPerson) -> some View {
        if let presence = member.visiblePresence {
            TrustBadge(glyph: presence == .home ? "house" : "figure.walk", text: presence.label)
        } else {
            TrustBadge(glyph: "lock", text: TrustCopy.presenceHiddenBadge)
        }
    }

    private func metaLine(at now: Date) -> String {
        var parts: [String] = []
        if let distance = distanceFromYou {
            parts.append(TrustCopy.distanceFromYou(distance))
        }
        if let point {
            let time = point.timestamp.formatted(date: .abbreviated, time: .shortened)
            parts.append(isAvailable
                ? "\(TrustCopy.locationFreshness(timestamp: point.timestamp, now: now)) · \(time)"
                : TrustCopy.snapshotAt(time))
        }
        return parts.joined(separator: " · ")
    }

    /// Hide the small duplicate map only when the leading People map already
    /// shows this exact point with the same live or snapshot meaning. A newer
    /// live point, a different snapshot, or an omitted pin keeps the detail map.
    private func leadingMapShowsCurrentPoint(_ point: LocationPoint) -> Bool {
        leadingMapPins.contains { pin in
            pin.id == personID && pin.point == point && pin.live == isAvailable
        }
    }

    private func directionSummary(_ member: TrustedPerson) -> some View {
        let inbound = shareLabel(member.inboundPresentation)
        let outbound = shareLabel(model.shareState(for: member.id).presentation(at: Date()))
        return Text(TrustCopy.sharingDirections(inbound: inbound, outbound: outbound))
            .trustFont(11)
            .foregroundStyle(palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("person-sharing-directions")
    }

    private func shareLabel(_ presentation: SharePresentation?) -> String {
        switch presentation {
        case .off, nil: return "Off"
        case .untilTheyLook: return TrustCopy.sealed
        case .always: return TrustCopy.always
        case .paused: return "Paused"
        }
    }

    private var distanceFromYou: String? {
        guard let point, let mine = model.location.lastFix else { return nil }
        let meters = CLLocation(latitude: point.latitude, longitude: point.longitude)
            .distance(from: CLLocation(latitude: mine.latitude, longitude: mine.longitude))
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = meters > 20_000 ? 0 : 1
        return formatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
    }

    /// Muted one-pin MapKit plate (`.local-map`). Pin is the person's initials.
    private func pinMap(_ point: LocationPoint, name: String) -> some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            Annotation(name, coordinate: point.coordinate) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    TrustMapPin(
                        initials: name.trustInitials,
                        live: isAvailable,
                        stale: isAvailable && LocationFreshness.status(timestamp: point.timestamp, now: context.date) == .stale,
                        ageCaption: isAvailable ? TrustCopy.locationAgeCaption(timestamp: point.timestamp, now: context.date) : nil
                    )
                    .accessibilityLabel(TrustCopy.pinAccessibility(name: name, live: isAvailable, timestamp: point.timestamp, now: context.date))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.line, lineWidth: 1))
        .onAppear { position = .region(Self.region(for: point)) }
        .onChange(of: point) { _, next in position = .region(Self.region(for: next)) }
        .accessibilityLabel(TrustCopy.pinAccessibility(name: name, live: isAvailable))
        .accessibilityIdentifier("view-embedded-map")
    }

    private static func region(for point: LocationPoint) -> MKCoordinateRegion {
        MKCoordinateRegion(center: point.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
    }

    private var seed: Int {
        model.circle.firstIndex { $0.id == personID } ?? 0
    }

    private func geocodeIfNeeded() async {
        guard let point, geocodedFor != point else { return }
        geocodedFor = point
        placeName = await PlaceNamer.name(for: point)
    }
}

struct PlaceName: Equatable {
    var primary: String
    var secondary: String?
}

/// Neighborhood · city for the View header. Best effort; the coordinate is already visible,
/// so a failed lookup only means a generic title.
enum PlaceNamer {
    static func name(for point: LocationPoint) async -> PlaceName? {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let neighborhood = placemark.subLocality
        let city = placemark.locality ?? placemark.administrativeArea
        if let neighborhood, !neighborhood.isEmpty {
            return PlaceName(primary: neighborhood, secondary: city)
        }
        if let city, !city.isEmpty {
            return PlaceName(primary: city, secondary: nil)
        }
        return nil
    }
}

/// Initials disc used as a map annotation. High-contrast fill for MapKit readability.
struct TrustMapPin: View {
    let initials: String
    var live = true
    var selected = false
    var stale = false
    var ageCaption: String?
    @Environment(\.trustPalette) private var palette

    var body: some View {
        VStack(spacing: 2) {
            Text(initials)
                .font(TrustTheme.chrome(13, weight: .bold))
                .foregroundStyle(palette.accentOn)
                .frame(width: 40, height: 40)
                .background(live ? palette.pinLive : palette.pinLook)
                .clipShape(Circle())
                .overlay(Circle().stroke(selected ? palette.accent : palette.chrome, lineWidth: 3))
                .overlay(alignment: .topTrailing) {
                    if stale {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.danger)
                            .frame(width: 16, height: 16)
                            .background(palette.chrome, in: Circle())
                            .offset(x: 3, y: -2)
                            .accessibilityHidden(true)
                    }
                }
                .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
            if let ageCaption {
                Text(ageCaption)
                    .font(TrustTheme.chrome(9, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(palette.paper.opacity(0.94), in: Capsule())
                    .lineLimit(1)
            }
        }
    }
}

extension LocationPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
