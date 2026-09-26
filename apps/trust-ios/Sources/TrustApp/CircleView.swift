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
    @State private var userMovedMap = false
    @State private var didFitInitialCamera = false
    @GestureState private var dragTranslation: CGFloat = 0

    private var pins: [AppModel.MapPin] { model.homeMapPins }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fullHeight = max(geo.size.height, 1)
            let isWide = width >= 760
            let panelWidth = min(390, max(330, width * 0.36))

            ZStack(alignment: .topLeading) {
                if isWide {
                    wideMap
                        .frame(width: width - panelWidth, height: fullHeight)
                        .overlay(alignment: .trailing) { palette.line.frame(width: 1) }
                }

                NavigationStack(path: $model.circlePath) {
                    Group {
                        if isWide {
                            widePeoplePanel
                        } else {
                            compactRoot(width: width, height: fullHeight)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: CircleRoute.self, destination: routeDestination)
                }
                .frame(width: isWide ? panelWidth : width, height: fullHeight)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: isWide ? .trailing : .leading
                )
            }
            .frame(width: width, height: fullHeight)
        }
        .onAppear {
            model.prepareMapLocation()
            fitAll()
        }
        .onChange(of: pins.map(\.id)) { _, _ in
            if !userMovedMap { fitAll() }
        }
        .onChange(of: model.location.lastFix) { _, fix in
            guard fix != nil, !didFitInitialCamera, !userMovedMap else { return }
            didFitInitialCamera = true
            fitAll()
        }
        .onChange(of: position.positionedByUser) { _, movedByUser in
            if movedByUser { userMovedMap = true }
        }
        .onDisappear { model.releaseMapLocation() }
    }

    private func compactRoot(width: CGFloat, height: CGFloat) -> some View {
        let sheetHeight = height * liveSheetFraction(containerHeight: height)
        return ZStack(alignment: .bottom) {
            homeMap
                .ignoresSafeArea(edges: .top)
            mapTitle
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            peopleSheet(
                height: sheetHeight,
                containerHeight: height,
                listInset: 20
            )
        }
        .frame(width: width, height: height, alignment: .bottom)
        .overlay(alignment: .bottomTrailing) {
            recenterButton
                .padding(.trailing, 16)
                .padding(.bottom, sheetHeight + 16)
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: CircleRoute) -> some View {
        switch route {
        case .person(let id):
            PersonScreen(personID: id)
        case .view(let id):
            ViewScreen(personID: id)
        case .map:
            MapScreen()
        }
    }

    // MARK: Map

    /// The wide People layout keeps the map and its controls in a stable leading pane.
    /// A width threshold lets fold and Stage Manager changes adapt to the space actually
    /// available instead of relying on a particular device's size class.
    private var wideMap: some View {
        ZStack(alignment: .topLeading) {
            homeMap
                .ignoresSafeArea(edges: .top)
            wideMapStatus
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            recenterButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(16)
        }
        .clipped()
    }

    private var widePeoplePanel: some View {
        VStack(spacing: 0) {
            HStack {
                TrustPageTitle(text: TrustCopy.people)
                Spacer(minLength: 8)
                Text("\(model.circle.count)")
                    .trustFont(13, weight: .semibold)
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(Capsule().fill(palette.surface))
                    .accessibilityLabel(TrustCopy.peopleCountAccessibility(model.circle.count))
            }
            .padding(.horizontal, TrustTheme.gutter)
            .padding(.top, 20)
            .padding(.bottom, 14)

            TrustRowDivider()
            sheetBody(listInset: 20)
        }
        .background(palette.paper)
        .accessibilityElement(children: .contain)
    }

    private var homeMap: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(pins) { pin in
                Annotation(pin.name, coordinate: pin.point.coordinate) {
                    Button {
                        if let member = model.member(pin.id) { model.openView(member) }
                    } label: {
                        TrustMapPin(initials: pin.name.trustInitials, live: pin.live)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(TrustCopy.pinAccessibility(name: pin.name, live: pin.live))
                    .accessibilityHint(TrustCopy.viewLocation(name: pin.name.trustFirstName))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {}
        .accessibilityLabel(TrustCopy.mapAccessibility)
    }

    private var mapTitle: some View {
        VStack(alignment: .leading, spacing: 5) {
            TrustPageTitle(text: TrustCopy.people, size: 28)
            Text(TrustCopy.onMap(count: pins.count, sealed: max(0, model.circle.count - pins.count)))
                .trustFont(12, weight: .medium)
                .foregroundStyle(palette.chromeMuted)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, TrustTheme.gutter)
        .padding(.top, 8)
        .allowsHitTesting(false)
    }

    private var wideMapStatus: some View {
        Text(TrustCopy.onMap(count: pins.count, sealed: max(0, model.circle.count - pins.count)))
            .trustFont(12, weight: .medium)
            .foregroundStyle(palette.chromeMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.horizontal, TrustTheme.gutter)
            .padding(.top, 8)
            .allowsHitTesting(false)
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
            Button {
                toggleDetent()
            } label: {
                Capsule()
                    .fill(palette.line)
                    .frame(width: 36, height: 5)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(sheetDrag(containerHeight: containerHeight))
            .accessibilityLabel(TrustCopy.peopleListSizeAccessibility)
            .accessibilityValue(PeopleSheetDetent.nearest(to: sheetFraction).accessibilityLabel)
            .accessibilityHint(TrustCopy.peopleListSizeHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction(adjustDetent)
            .accessibilityIdentifier("people-sheet-detent")

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
                        glyph: "person.2.wave.2",
                        title: TrustCopy.circleEmptyTitle,
                        message: TrustCopy.circleEmptyBody,
                        actionTitle: "Go to Sharing"
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
                        if sharing.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(TrustCopy.peopleEmptyTitle)
                                    .trustFont(17, weight: .semibold)
                                    .foregroundStyle(palette.ink)
                                Text(TrustCopy.peopleEmptyBody)
                                    .trustFont(13)
                                    .foregroundStyle(palette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button(TrustCopy.goToSharing) { model.selectedTab = .sharing }
                                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.surface))
                            .padding(.top, 4)
                        } else {
                            TrustSectionHeading(TrustCopy.sharedWithYou)
                                .padding(.top, 2)
                            ForEach(sharing) { member in
                                CirclePersonRow(member: member, seed: seed(member))
                                TrustRowDivider()
                            }
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

    private func adjustDetent(_ direction: AccessibilityAdjustmentDirection) {
        let detents = PeopleSheetDetent.allCases
        guard let current = detents.firstIndex(of: .nearest(to: sheetFraction)) else { return }
        let next: Int
        switch direction {
        case .increment: next = min(current + 1, detents.count - 1)
        case .decrement: next = max(current - 1, 0)
        @unknown default: return
        }
        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
            sheetFraction = detents[next].rawValue
        }
    }

    private func toggleDetent() {
        let current = PeopleSheetDetent.nearest(to: sheetFraction)
        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
            sheetFraction = (current == .expanded ? PeopleSheetDetent.half : .expanded).rawValue
        }
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
        withAnimation(.easeInOut(duration: 0.35)) {
            if let region = metroRegion(for: coordinates) {
                position = .region(region)
            } else {
                position = .automatic
            }
        }
    }

    /// Street-level camera. Pins spread across cities must not zoom the home map out to a globe.
    private func metroRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else {
            if let fix = model.location.lastFix {
                return MKCoordinateRegion(center: fix.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
            }
            return nil
        }
        let nearby = model.location.lastFix.map { fix in coordinates.filter { coordinate in
            abs(coordinate.latitude - fix.latitude) < 0.35
                && abs(coordinate.longitude - fix.longitude) < 0.45
        }} ?? coordinates
        let focus = nearby.isEmpty ? coordinates : nearby
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
        let localCluster = model.location.lastFix != nil && !nearby.isEmpty
        let maxLatitudeSpan: CLLocationDegrees = localCluster ? 0.12 : 170
        let maxLongitudeSpan: CLLocationDegrees = localCluster ? 0.12 : 320
        let span = MKCoordinateSpan(
            latitudeDelta: min(maxLatitudeSpan, max((maxLat - minLat) * 1.6, 0.045)),
            longitudeDelta: min(maxLongitudeSpan, max((maxLon - minLon) * 1.6, 0.045))
        )
        return MKCoordinateRegion(center: center, span: span)
    }

}

private enum PeopleSheetDetent: CGFloat, CaseIterable {
    case peek = 0.28
    case half = 0.55
    case expanded = 0.82

    var accessibilityLabel: String {
        switch self {
        case .peek: return "Compact"
        case .half: return "Half height"
        case .expanded: return "Expanded"
        }
    }

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isNotSharing: Bool { member.isNotSharingWithYou }

    private var canPeek: Bool {
        TrustProductRules.peek(inbound: member.inboundPresentation ?? .off) != .none
    }

    private var peekIsLook: Bool {
        TrustProductRules.peek(inbound: member.inboundPresentation ?? .off) == .look && !model.isOpened(member)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    personButton(multiline: true)
                    if canPeek {
                        HStack { Spacer(minLength: 0); peekButton }
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    personButton(multiline: false)
                    if canPeek { peekButton }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    }

    private func personButton(multiline: Bool) -> some View {
        Button {
            model.openPerson(member)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                TrustAvatar(name: member.person.displayName, seed: seed, size: 44, avatar: member.person.avatar, personID: member.id)
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.person.displayName)
                        .trustFont(16, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .lineLimit(multiline ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: multiline)
                    Text(statusText)
                        .trustFont(13)
                        .foregroundStyle(palette.muted)
                        .lineLimit(multiline ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: multiline)
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(member.person.displayName). \(statusText)")
        .accessibilityIdentifier("person-row-\(member.firstName.lowercased())")
    }

    @ViewBuilder
    private var peekButton: some View {
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
                .frame(minWidth: 66, minHeight: 44)
                .background(Capsule().stroke(peekIsLook ? palette.accentSoft : palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(peekIsLook ? TrustCopy.lookHint(name: member.firstName) : TrustCopy.viewHint(name: member.firstName))
        .accessibilityIdentifier("person-peek-\(member.firstName.lowercased())")
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
                .accessibilityIdentifier("circle-back")
            }
        }
    }

    private func content(_ member: TrustedPerson) -> some View {
        let history = model.locationHistory(for: member)
        return Group {
            if !member.isAvailable {
                empty(member)
            } else if !model.isDemoMode && (model.historyLoadingIDs.contains(member.id) || (!model.historyLoadedIDs.contains(member.id) && !model.historyErrors.contains(member.id))) {
                historyProgress(member)
            } else if model.historyErrors.contains(member.id) {
                historyError(member)
            } else if history.isEmpty {
                historyEmpty(member)
            } else {
                historyList(member, history: history)
            }
        }
        .task(id: history.map(\.id)) {
            await geocode(history)
        }
        .task(id: member.isAvailable) {
            if member.isAvailable { await model.loadHistory(for: member.id) }
        }
    }

    private func historyProgress(_ member: TrustedPerson) -> some View {
        VStack(spacing: 14) {
            TrustAvatar(name: member.person.displayName, seed: seed, size: 72, avatar: member.person.avatar, personID: member.id)
            Text(member.person.displayName).font(TrustTheme.display(28)).foregroundStyle(palette.ink)
            ProgressView().tint(palette.accent)
            Text(TrustCopy.loadingRecentPlaces)
                .trustFont(14)
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("person-history-loading")
    }

    private func historyError(_ member: TrustedPerson) -> some View {
        TrustEmptyState(
            glyph: "exclamationmark.triangle",
            title: "Places unavailable",
            message: "Recent places could not be loaded.",
            actionTitle: "Try again"
        ) {
            Task { await model.loadHistory(for: member.id) }
        }
        .accessibilityIdentifier("person-history-error")
    }

    private func historyEmpty(_ member: TrustedPerson) -> some View {
        TrustEmptyState(
            glyph: "location",
            title: "No recent places",
            message: "New places will appear here while Always sharing is on.",
            actionTitle: TrustCopy.backToCircle
        ) {
            model.circlePath = []
        }
        .accessibilityIdentifier("person-history-empty")
    }

    private func empty(_ member: TrustedPerson) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            TrustAvatar(name: member.person.displayName, seed: seed, size: 88, avatar: member.person.avatar, personID: member.id)
            TrustPageTitle(text: member.person.displayName, size: 32)
                .multilineTextAlignment(.center)
            Text(statusText(member))
                .trustFont(17)
                .foregroundStyle(palette.muted)
                .accessibilityIdentifier("person-status")
            Text(directionText(member))
                .trustFont(13)
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("person-sharing-directions")
            if canPeek(member) {
                Button(peekTitle(member)) {
                    peek(member)
                }
                .buttonStyle(TrustFilledButtonStyle())
                .accessibilityIdentifier("person-profile-peek")
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
                    TrustAvatar(name: member.person.displayName, seed: seed, size: 64, avatar: member.person.avatar, personID: member.id)
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

                Text(directionText(member))
                    .trustFont(12)
                    .foregroundStyle(palette.muted)
                    .padding(.bottom, 14)
                    .accessibilityIdentifier("person-sharing-directions")

                ForEach(Array(history.enumerated()), id: \.element.id) { index, visit in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(label(for: visit))
                            .trustFont(16, weight: index == 0 ? .semibold : .regular)
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(visit.at.formatted(date: .abbreviated, time: .shortened))
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
        .accessibilityIdentifier("person-history")
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

    private func directionText(_ member: TrustedPerson) -> String {
        let inbound = shareLabel(member.inboundPresentation)
        let outbound = shareLabel(model.shareState(for: member.id).presentation(at: Date()))
        return "They share with you: \(inbound) · You share with them: \(outbound)"
    }

    private func shareLabel(_ presentation: SharePresentation?) -> String {
        switch presentation {
        case .off, nil: return "Off"
        case .untilTheyLook: return TrustCopy.sealed
        case .always: return TrustCopy.always
        case .paused: return "Paused"
        }
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
