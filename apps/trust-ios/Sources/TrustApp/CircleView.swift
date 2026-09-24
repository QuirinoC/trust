import MapKit
import SwiftUI
import TrustCore

/// T1 People — map, recenter, draggable list. No top pill.
struct CircleView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @State private var position: MapCameraPosition = .automatic
    @State private var sheetFraction: CGFloat = PeopleSheetDetent.half.rawValue
    @State private var dragOrigin: CGFloat?
    @GestureState private var dragTranslation: CGFloat = 0

    private var pins: [AppModel.MapPin] { model.homeMapPins }

    var body: some View {
        NavigationStack(path: $model.circlePath) {
            GeometryReader { geo in
                let width = geo.size.width
                let fullHeight = max(geo.size.height, 1)
                let sheetHeight = fullHeight * liveSheetFraction(containerHeight: fullHeight)
                ZStack(alignment: .bottom) {
                    homeMap
                        .ignoresSafeArea(edges: .top)
                    peopleSheet(
                        height: sheetHeight,
                        containerHeight: fullHeight,
                        listInset: 20
                    )
                }
                .frame(width: width, height: fullHeight, alignment: .bottom)
                .overlay(alignment: .bottomTrailing) {
                    recenterButton
                        .padding(.trailing, 16)
                        .padding(.bottom, sheetHeight + 16)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CircleRoute.self) { route in
                switch route {
                case .person(let id):
                    PersonScreen(personID: id)
                case .view(let id):
                    ViewScreen(personID: id)
                case .map:
                    MapScreen()
                }
            }
        }
        .onAppear {
            model.prepareMapLocation()
            fitAll()
        }
        .onChange(of: pins.map(\.id)) { _, _ in fitAll() }
        .onDisappear { model.releaseMapLocation() }
    }

    // MARK: Map

    private var homeMap: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(pins) { pin in
                Annotation(pin.name, coordinate: pin.point.coordinate) {
                    TrustMapPin(
                        initials: pin.name.trustInitials,
                        live: pin.live,
                        selected: false
                    )
                    .accessibilityLabel(TrustCopy.pinAccessibility(name: pin.name, live: pin.live))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {}
        .accessibilityLabel(TrustCopy.mapAccessibility)
    }

    private var recenterButton: some View {
        Button {
            fitAll(includeUser: true)
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.chromeInk)
                .frame(width: 44, height: 44)
                .background(palette.chrome)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .accessibilityLabel(TrustCopy.recenterMap)
    }

    // MARK: Sheet

    private func peopleSheet(height: CGFloat, containerHeight: CGFloat, listInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: 0xC9CAC2))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(sheetDrag(containerHeight: containerHeight))

            sheetBody(listInset: listInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(palette.sheet)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 16, y: -4)
        .accessibilityElement(children: .contain)
    }

    private func sheetBody(listInset: CGFloat) -> some View {
        Group {
            if model.circle.isEmpty {
                ScrollView {
                    TrustEmptyState(
                        glyph: "lock",
                        title: TrustCopy.circleEmptyTitle,
                        message: TrustCopy.circleEmptyBody,
                        actionTitle: TrustCopy.addSomeone
                    ) {
                        model.selectedTab = .sharing
                    }
                    .padding(.horizontal, TrustTheme.gutter)
                    .padding(.bottom, listInset)
                }
                .refreshable { await model.refresh() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TrustSectionHeading(TrustCopy.sharedWithYou)
                            .padding(.top, 2)

                        ForEach(sharing) { member in
                            CirclePersonRow(member: member, seed: seed(member))
                            TrustRowDivider()
                        }

                        if !notSharing.isEmpty {
                            TrustSectionHeading(TrustCopy.notSharingWithYou)
                                .padding(.top, 18)
                            ForEach(notSharing) { member in
                                CirclePersonRow(member: member, seed: seed(member))
                                TrustRowDivider()
                            }
                        }
                    }
                    .padding(.horizontal, TrustTheme.gutter)
                    .padding(.bottom, listInset)
                    .trustReadableWidth()
                }
                .refreshable { await model.refresh() }
            }
        }
    }

    private func sheetDrag(containerHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = sheetFraction
                }
                guard let origin = dragOrigin else { return }
                let delta = -value.translation.height / containerHeight
                sheetFraction = (origin + delta)
                    .clamped(to: PeopleSheetDetent.peek.rawValue...PeopleSheetDetent.expanded.rawValue)
            }
            .onEnded { value in
                let origin = dragOrigin ?? sheetFraction
                let delta = -value.translation.height / containerHeight
                let projected = origin + delta
                    + (-value.predictedEndTranslation.height / containerHeight) * 0.12
                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
                    sheetFraction = PeopleSheetDetent.nearest(to: projected).rawValue
                }
                dragOrigin = nil
            }
    }

    private func liveSheetFraction(containerHeight: CGFloat) -> CGFloat {
        if let origin = dragOrigin {
            return (origin + (-dragTranslation / containerHeight))
                .clamped(to: PeopleSheetDetent.peek.rawValue...PeopleSheetDetent.expanded.rawValue)
        }
        return sheetFraction
    }

    // MARK: List helpers

    private var sharing: [TrustedPerson] {
        model.circle.filter { !isNotSharing($0) }
    }

    private var notSharing: [TrustedPerson] {
        model.circle.filter { isNotSharing($0) }
    }

    private func isNotSharing(_ member: TrustedPerson) -> Bool {
        member.isNotSharingWithYou
    }

    private func seed(_ member: TrustedPerson) -> Int {
        model.circle.firstIndex { $0.id == member.id } ?? 0
    }

    private func fitAll(includeUser: Bool = false) {
        var coordinates = pins.map(\.point.coordinate)
        if includeUser, let fix = model.location.lastFix {
            coordinates.append(fix.coordinate)
        }
        let region = metroRegion(for: coordinates) ?? Self.neighborhood
        withAnimation(.easeInOut(duration: 0.35)) {
            position = .region(region)
        }
    }

    /// Street-level camera. Pins spread across cities must not zoom the home map out to a globe.
    private func metroRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        let anchor = model.location.lastFix?.coordinate ?? Self.neighborhood.center
        let nearby = coordinates.filter { coordinate in
            abs(coordinate.latitude - anchor.latitude) < 0.35
                && abs(coordinate.longitude - anchor.longitude) < 0.45
        }
        let focus = nearby.isEmpty ? (coordinates.isEmpty ? [] : [anchor]) : nearby
        guard let first = focus.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in focus.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: min(0.12, max((maxLat - minLat) * 1.6, 0.045)),
            longitudeDelta: min(0.12, max((maxLon - minLon) * 1.6, 0.045))
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Mission, San Francisco — the demo neighborhood when no local pin or fix is ready.
    private static let neighborhood = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7599, longitude: -122.4148),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
}

private enum PeopleSheetDetent: CGFloat, CaseIterable {
    case peek = 0.28
    case half = 0.55
    case expanded = 0.82

    static func nearest(to value: CGFloat) -> PeopleSheetDetent {
        allCases.min(by: { abs($0.rawValue - value) < abs($1.rawValue - value) }) ?? .half
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Row opens the person (presence + place history). Look / View is a separate peek.
struct CirclePersonRow: View {
    let member: TrustedPerson
    var seed: Int = 0
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    private var isNotSharing: Bool { member.isNotSharingWithYou }

    private var canPeek: Bool {
        TrustProductRules.peek(inbound: member.inboundPresentation ?? .off) != .none
    }

    private var peekIsLook: Bool {
        TrustProductRules.peek(inbound: member.inboundPresentation ?? .off) == .look && !model.isOpened(member)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                model.openPerson(member)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    TrustAvatar(name: member.person.displayName, seed: seed, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(member.person.displayName)
                            .trustFont(16, weight: .semibold)
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Text(statusText)
                            .trustFont(13)
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(member.person.displayName). \(statusText)")

            if canPeek {
                Button {
                    if peekIsLook {
                        model.openLook(member)
                    } else {
                        model.openView(member)
                    }
                } label: {
                    Text(peekIsLook ? TrustCopy.look : TrustCopy.view)
                        .trustFont(13, weight: .semibold)
                        .foregroundStyle(peekIsLook ? palette.accent : palette.muted)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 66, minHeight: 34)
                        .background(
                            Capsule().stroke(
                                peekIsLook ? Color(hex: 0xF0C8BE) : palette.line,
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(peekIsLook ? TrustCopy.lookHint(name: member.firstName) : TrustCopy.viewHint(name: member.firstName))
            }
        }
        .padding(.vertical, 14)
        .frame(minHeight: 64)
    }

    private var statusText: String {
        if member.isPaused { return TrustCopy.pause }
        if isNotSharing { return TrustCopy.choseOff(name: member.firstName) }
        if let presence = member.visiblePresence { return presence.label }
        return TrustCopy.presenceHiddenBadge
    }
}

/// Person — Home / Away, then place history. Not the Look map.
struct PersonScreen: View {
    let personID: UUID
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @State private var placeNames: [UUID: String] = [:]

    private var member: TrustedPerson? { model.member(personID) }

    private var isNotSharing: Bool {
        member?.isNotSharingWithYou == true
    }

    var body: some View {
        Group {
            if let member {
                content(member)
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
    }

    private func content(_ member: TrustedPerson) -> some View {
        let history = model.locationHistory(for: member)
        return Group {
            if history.isEmpty {
                empty(member)
            } else {
                historyList(member, history: history)
            }
        }
        .task(id: history.map(\.id)) {
            await geocode(history)
        }
    }

    private func empty(_ member: TrustedPerson) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            TrustAvatar(name: member.person.displayName, seed: seed, size: 88)
            TrustPageTitle(text: member.person.displayName, size: 32)
                .multilineTextAlignment(.center)
            Text(statusText(member))
                .trustFont(17)
                .foregroundStyle(palette.muted)
            if canPeek(member) {
                Button(peekTitle(member)) {
                    peek(member)
                }
                .buttonStyle(TrustFilledButtonStyle())
                .padding(.top, 8)
                Text(peekIsLook(member) ? TrustCopy.lookNotifiedShort : TrustCopy.kindView)
                    .trustFont(13)
                    .foregroundStyle(palette.muted)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, TrustTheme.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .trustReadableWidth()
    }

    private func historyList(_ member: TrustedPerson, history: [LocationVisit]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    TrustAvatar(name: member.person.displayName, seed: seed, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        TrustPageTitle(text: member.person.displayName, size: 30)
                        Text(statusText(member))
                            .trustFont(15)
                            .foregroundStyle(palette.muted)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 22)
                .accessibilityElement(children: .combine)

                ForEach(Array(history.enumerated()), id: \.element.id) { index, visit in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(label(for: visit))
                            .trustFont(16, weight: index == 0 ? .semibold : .regular)
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(visit.at.formatted(date: .omitted, time: .shortened))
                            .trustFont(13)
                            .foregroundStyle(palette.muted)
                    }
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                    TrustRowDivider()
                }
            }
            .padding(.horizontal, TrustTheme.gutter)
            .padding(.bottom, 28)
            .trustReadableWidth()
        }
    }

    private func canPeek(_ member: TrustedPerson) -> Bool {
        TrustProductRules.peek(inbound: member.inboundPresentation ?? .off) != .none
    }

    private func peekIsLook(_ member: TrustedPerson) -> Bool {
        TrustProductRules.peek(inbound: member.inboundPresentation ?? .off) == .look
    }

    private func peekTitle(_ member: TrustedPerson) -> String {
        peekIsLook(member) ? TrustCopy.look : TrustCopy.view
    }

    private func peek(_ member: TrustedPerson) {
        if peekIsLook(member) {
            model.openLook(member)
        } else {
            model.openView(member)
        }
    }

    private func statusText(_ member: TrustedPerson) -> String {
        if member.isPaused { return TrustCopy.pause }
        if member.isNotSharingWithYou { return TrustCopy.choseOff(name: member.firstName) }
        if let presence = member.visiblePresence { return presence.label }
        return TrustCopy.presenceHiddenBadge
    }

    private func label(for visit: LocationVisit) -> String {
        if let named = placeNames[visit.id] { return named }
        if visit.label != TrustCopy.location { return visit.label }
        return TrustCopy.location
    }

    private var seed: Int {
        model.circle.firstIndex { $0.id == personID } ?? 0
    }

    private func geocode(_ history: [LocationVisit]) async {
        for visit in history where visit.label == TrustCopy.location {
            guard placeNames[visit.id] == nil, let point = visit.point else { continue }
            if let name = await PlaceNamer.name(for: point)?.primary {
                placeNames[visit.id] = name
            }
        }
    }
}
