import CoreLocation
import MapKit
import SwiftUI
import TrustCore

/// D1 View — one person. Snapshot (after a Look) or live (Available). Receipt line names
/// what just happened; the map is muted and secondary.
struct ViewScreen: View {
    let personID: UUID
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @State private var placeName: PlaceName?
    @State private var position: MapCameraPosition = .automatic
    @State private var geocodedFor: LocationPoint?

    private var member: TrustedPerson? { model.member(personID) }
    private var snapshot: LookSession? { model.openedSnapshot(for: personID) }
    private var isAvailable: Bool { member?.isAvailable ?? false }

    private var point: LocationPoint? {
        if isAvailable, let live = member?.livePoint { return live }
        return snapshot?.live
    }

    var body: some View {
        Group {
            if let member {
                if point != nil {
                    content(member)
                } else if member.isSealed, snapshot == nil {
                    sealed(member)
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
                    TrustAvatar(name: member.person.displayName, seed: seed, size: 70)
                    VStack(alignment: .leading, spacing: 7) {
                        TrustPageTitle(text: member.firstName, size: 32)
                        Text(isAvailable ? TrustCopy.liveShare : TrustCopy.oneTimeLook)
                            .trustFont(12)
                            .foregroundStyle(palette.muted)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 22)

                presenceBadge(member)

                VStack(alignment: .leading, spacing: 2) {
                    Text(placeName?.primary ?? (isAvailable ? TrustCopy.location : TrustCopy.snapshot))
                        .font(TrustTheme.display(32))
                        .tracking(-1)
                        .foregroundStyle(palette.ink)
                    if let secondary = placeName?.secondary {
                        Text(secondary)
                            .font(TrustTheme.display(32))
                            .tracking(-1)
                            .foregroundStyle(palette.muted)
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)

                Text(metaLine)
                    .trustFont(13)
                    .foregroundStyle(Color(hex: 0x72786A))

                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(isAvailable
                        ? TrustCopy.receiptViewLogged(name: member.firstName)
                        : TrustCopy.receiptNotified(name: member.firstName))
                }
                .font(TrustTheme.ui(12, weight: .medium))
                .foregroundStyle(Color(hex: 0x6E7B61))
                .padding(.top, 18)
                .padding(.bottom, 20)

                if let point {
                    if let snapshot, snapshot.event.historyWindowHours > 0, snapshot.trail.count > 1 {
                        trailMap(snapshot.trail, live: snapshot.live, name: member.person.displayName)
                            .padding(.bottom, 14)
                    } else {
                        pinMap(point, name: member.person.displayName)
                            .padding(.bottom, 14)
                    }
                }

                if !isAvailable, let snapshot, snapshot.event.historyWindowHours <= 0 {
                    Button(TrustCopy.seeTrail(hours: model.coverage.historyHours)) {
                        model.extendOpenLook(personID: personID)
                    }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
                    .padding(.bottom, 10)
                }

                HStack(spacing: 10) {
                    Button {
                        model.circlePath = [.map]
                    } label: {
                        Label(TrustCopy.circleMap, systemImage: "map")
                    }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
                    Button {
                        model.circlePath = []
                    } label: {
                        HStack(spacing: 6) {
                            Text(TrustCopy.back)
                            Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
                }

                TrustInfoStrip(
                    glyph: isAvailable ? "eye" : (snapshot?.event.historyWindowHours ?? 0) > 0 ? "point.topleft.down.to.point.bottomright.curvepath" : "lock",
                    text: isAvailable
                        ? TrustCopy.stripLive
                        : (snapshot?.event.historyWindowHours ?? 0) > 0 ? TrustCopy.stripTrail : TrustCopy.stripSnapshot
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

    private var metaLine: String {
        var parts: [String] = []
        if let distance = distanceFromYou {
            parts.append(TrustCopy.distanceFromYou(distance))
        }
        if let point {
            let time = point.timestamp.formatted(date: .omitted, time: .shortened)
            parts.append(isAvailable ? TrustCopy.updatedAt(time) : TrustCopy.snapshotAt(time))
        }
        return parts.joined(separator: " · ")
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
                TrustMapPin(initials: name.trustInitials, live: isAvailable)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: 0xDFE4D6), lineWidth: 1))
        .onAppear { position = .region(Self.region(for: point)) }
        .onChange(of: point) { _, next in position = .region(Self.region(for: next)) }
        .accessibilityLabel(TrustCopy.pinAccessibility(name: name, live: isAvailable))
    }

    /// Open Look trail — retained points for this Look only (not a Log breadcrumb).
    private func trailMap(_ trail: [LocationPoint], live: LocationPoint, name: String) -> some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            ForEach(Array(trail.enumerated()), id: \.offset) { index, point in
                Annotation(index == trail.count - 1 ? name : "", coordinate: point.coordinate) {
                    if index == trail.count - 1 {
                        TrustMapPin(initials: name.trustInitials, live: false)
                    } else {
                        Circle()
                            .fill(Color(hex: 0xA8B09A).opacity(0.85))
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: 0xDFE4D6), lineWidth: 1))
        .onAppear { position = .region(Self.region(for: live)) }
        .accessibilityLabel(TrustCopy.pinAccessibility(name: name, live: false))
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
            return PlaceName(primary: city, secondary: placemark.country)
        }
        return nil
    }
}

/// Initials disc used as a map annotation. High-contrast fill for MapKit readability.
struct TrustMapPin: View {
    let initials: String
    var live = true
    var selected = false
    @Environment(\.trustPalette) private var palette

    var body: some View {
        Text(initials)
            .font(TrustTheme.chrome(13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(live ? palette.pinLive : palette.pinLook)
            .clipShape(Circle())
            .overlay(Circle().stroke(selected ? palette.accent : palette.chrome, lineWidth: 3))
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
    }
}

extension LocationPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
