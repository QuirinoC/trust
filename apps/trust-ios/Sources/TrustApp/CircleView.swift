import MapKit
import SwiftUI
import TrustCore

/// T1 People — map, recenter, draggable list. No top pill.
struct CircleView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var position: MapCameraPosition = .automatic
    @State private var sheetFraction: CGFloat = PeopleSheetDetent.half.rawValue
    @State private var dragOrigin: CGFloat?
    @State private var userMovedMap = false
    @State private var didFitInitialCamera = false
    @State private var mapViewportSize: CGSize = .zero
    @State private var mapViewportLocalBounds: CGRect = .zero
    @State private var mapViewportSafeInsets: [CGFloat] = [0, 0, 0, 0]
    @State private var requestedMapRect: MKMapRect?
    @State private var requestedCameraDistance: Double?
    @State private var mapAnnotationSizes: [UUID: CGSize] = [:]
    @State private var mapCaptionSizes: [UUID: CGSize] = [:]
    @State private var displayedCaptionPlacements: [UUID: TrustMapCaptionPlacement] = [:]
    @State private var captionLayoutTask: Task<Void, Never>?
    @State private var captionLayoutGeneration = 0
    @State private var lastSettledCamera: MapCamera?
    @State private var cameraCorrectionAttempts = 0
    @State private var pendingCameraCorrectionOverflow: CGFloat?
    @State private var cameraZoomOutWasClamped = false
    @State private var fallbackCameraTargetID: UUID?
    @State private var fallbackViewportAtFocus: CGSize?
    @State private var isAutomaticPeopleFit = false
    @State private var isExplicitRecenterFit = false
    @State private var recenterIntentGeneration = 0
    @State private var pendingRecenterGeneration: Int?
    @State private var cameraSettledRevision = 0
    @State private var cameraCorrectionAppliedRevision = -1
    @State private var cameraFitGeneration = 0
    @State private var cameraCorrectionTask: Task<Void, Never>?
    @State private var cameraCorrectionRequestToken = 0
    @State private var usesNativeAutomaticFit = false
    @State private var mapViewportFitTask: Task<Void, Never>?
    @State private var compactHeaderHeight: CGFloat = 76
    @GestureState private var dragTranslation: CGFloat = 0

    private var pins: [AppModel.MapPin] { model.homeMapPins }
    private var pinLocations: [CircleMapPinLocation] { pins.map(CircleMapPinLocation.init) }

    var body: some View {
        Group {
            if model.selectedTab == .circle {
                activeCircleContent
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
    }

    private var activeCircleContent: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fullHeight = max(geo.size.height, 1)
            // At 650pt the existing 330pt minimum People panel leaves a 320pt map.
            // This lets the unfolded Duo use the side-by-side layout at its actual
            // available width while preserving the same NavigationStack and routes.
            let isWide = width >= 650
            let panelWidth = min(390, max(330, width * 0.36))
            let mapRouteIsWide = isWide && model.circlePath.last == .map
            let showsPeopleLeadingMap = isWide && !mapRouteIsWide

            ZStack(alignment: .topLeading) {
                if showsPeopleLeadingMap {
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
                    .navigationDestination(for: CircleRoute.self) { route in
                        routeDestination(route, isWide: isWide)
                    }
                }
                .frame(width: showsPeopleLeadingMap ? panelWidth : width, height: fullHeight)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: showsPeopleLeadingMap ? .trailing : .leading
                )
            }
            .frame(width: width, height: fullHeight)
        }
        .onAppear {
            model.prepareMapLocation()
            fitOrFocusSelectedView()
        }
        .onChange(of: pinLocations) { _, _ in
            if let fallbackCameraTargetID,
               !pins.contains(where: { $0.id == fallbackCameraTargetID }) {
                self.fallbackCameraTargetID = nil
                fallbackViewportAtFocus = nil
                cameraZoomOutWasClamped = false
            }
            resetCameraBoundsCorrection(preservingSettledCamera: usesNativeAutomaticFit)
            fitOrFocusSelectedView(animated: false)
        }
        .onChange(of: mapViewportLocalBounds) { _, bounds in
            let viewportSize = bounds.size
            let viewportChangedMeaningfully = fallbackViewportAtFocus.map { originalSize in
                abs(viewportSize.width - originalSize.width) >= 32
                    || abs(viewportSize.height - originalSize.height) >= 32
            } ?? false
            if fallbackCameraTargetID != nil,
               viewportChangedMeaningfully,
               !userMovedMap,
               !isShowingSpecificPersonView {
                fallbackCameraTargetID = nil
                fallbackViewportAtFocus = nil
                cameraZoomOutWasClamped = false
            }
            resetCameraBoundsCorrection(preservingSettledCamera: usesNativeAutomaticFit)
            guard bounds.width > 0, bounds.height > 0 else { return }
            if usesNativeAutomaticFit, lastSettledCamera != nil {
                cameraCorrectionRequestToken &+= 1
            } else {
                scheduleViewportCameraFit()
            }
        }
        .onChange(of: model.circlePath) { _, path in
            invalidatePendingRecenter(reason: "navigation")
            resetCameraBoundsCorrection(preservingSettledCamera: usesNativeAutomaticFit)
            if case let .view(personID)? = path.last {
                // Entering a specific person's view should reveal their pin,
                // even when the person previously panned the map manually.
                // A new manual pan inside View can suspend following again.
                userMovedMap = false
                focusMap(on: personID)
            } else {
                fitOrFocusSelectedView()
            }
        }
        .onChange(of: model.location.lastFix) { previousFix, fix in
            guard fix != nil, !userMovedMap else { return }
            if previousFix == nil {
                fallbackCameraTargetID = nil
                fallbackViewportAtFocus = nil
                cameraZoomOutWasClamped = false
                didFitInitialCamera = true
                fitOrFocusSelectedView()
            } else if !didFitInitialCamera {
                didFitInitialCamera = true
                fitOrFocusSelectedView()
            } else if fallbackCameraTargetID != nil,
                      !isShowingSpecificPersonView,
                      let fix,
                      hasNearbyAuthorizedPinCluster(around: fix.coordinate),
                      let previousFix,
                      !hasNearbyAuthorizedPinCluster(around: previousFix.coordinate) {
                // A later GPS fix can turn a formerly far-away People map into a
                // normal nearby fit. Refit only on that transition, never for
                // every location update, and preserve a selected-person view/pan.
                fallbackCameraTargetID = nil
                fallbackViewportAtFocus = nil
                cameraZoomOutWasClamped = false
                fitOrFocusSelectedView()
            }
        }
        .onChange(of: position.positionedByUser) { _, movedByUser in
            model.traceUIInteraction("people map user moved=\(movedByUser)")
            if movedByUser {
                invalidatePendingRecenter(reason: "user-map-gesture")
                userMovedMap = true
                usesNativeAutomaticFit = false
                fallbackCameraTargetID = nil
                fallbackViewportAtFocus = nil
                cameraZoomOutWasClamped = false
                resetCameraBoundsCorrection()
            }
        }
        .onDisappear {
            invalidatePendingRecenter(reason: "map-disappeared")
            mapViewportFitTask?.cancel()
            mapViewportFitTask = nil
            captionLayoutTask?.cancel()
            captionLayoutTask = nil
            captionLayoutGeneration &+= 1
            resetCameraBoundsCorrection()
            model.releaseMapLocation()
        }
    }

    private func compactRoot(width: CGFloat, height: CGFloat) -> some View {
        let requestedSheetHeight = height * liveSheetFraction(containerHeight: height)
        // Keep enough of the map visible for a complete pin and its age caption,
        // even when Dynamic Type makes the header taller or the device is short.
        let maximumSheetHeight = max(44, height - compactHeaderHeight - 176)
        let sheetHeight = min(requestedSheetHeight, maximumSheetHeight)
        return VStack(spacing: 0) {
            compactMapHeader
            homeMap
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            peopleSheet(
                height: sheetHeight,
                containerHeight: height,
                listInset: 20
            )
        }
        .background(palette.paper)
        .frame(width: width, height: height, alignment: .bottom)
    }

    @ViewBuilder
    private func routeDestination(_ route: CircleRoute, isWide: Bool) -> some View {
        switch route {
        case .person(let id):
            PersonScreen(personID: id)
        case .view(let id):
            ViewScreen(personID: id, leadingMapPins: isWide ? model.homeMapPins : [])
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
        MapReader { proxy in
            let captionLayout = displayedCaptionPlacements
            Map(position: $position) {
                UserAnnotation()
                ForEach(pins) { pin in
                    let captionSize = pin.live ? mapCaptionSizes[pin.id] : nil
                    let placement = captionLayout[pin.id] ?? .centeredBelow
                    let stale = pin.live && LocationFreshness.status(timestamp: pin.point.timestamp, now: .now) == .stale
                    let pinLayout: TrustMapPinGeometryLayout? = pin.live && captionSize == nil
                        ? nil
                        : TrustMapCaptionLayout.pinGeometry(
                            anchor: .bottom,
                            captionSize: captionSize,
                            placement: placement,
                            stale: stale,
                            minimumFrame: CGSize(width: 44, height: 44)
                        )
                    let annotationAnchor = pinLayout.map {
                        UnitPoint(x: $0.annotationAnchor.x, y: $0.annotationAnchor.y)
                    } ?? .bottom
                    Annotation(pin.name, coordinate: pin.point.coordinate, anchor: annotationAnchor) {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Button {
                                activateMapPin(pin.id)
                            } label: {
                                TrustMapPin(
                                    initials: pin.name.trustInitials,
                                    live: pin.live,
                                    stale: pin.live && LocationFreshness.status(timestamp: pin.point.timestamp, now: context.date) == .stale,
                                    ageCaption: pin.live ? TrustCopy.locationAgeCaption(timestamp: pin.point.timestamp, now: context.date) : nil,
                                    pinLayout: pinLayout,
                                    onCaptionSizeChange: { size in
                                        guard mapCaptionSizes[pin.id] != size else { return }
                                        mapCaptionSizes[pin.id] = size
                                    }
                                )
                                .frame(minWidth: 44, minHeight: 44)
                                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                                    guard size.width > 0, size.height > 0,
                                          mapAnnotationSizes[pin.id] != size else { return }
                                    mapAnnotationSizes[pin.id] = size
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(TrustCopy.pinAccessibility(name: pin.name, live: pin.live, timestamp: pin.point.timestamp, now: context.date))
                            .accessibilityHint(TrustCopy.viewLocation(name: pin.name.trustFirstName))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("people-map-pin-\(pin.id.uuidString.lowercased())")
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls {}
            .accessibilityLabel(TrustCopy.mapAccessibility)
            .accessibilityIdentifier("people-map-canvas")
            .onGeometryChange(for: [CGFloat].self) { geometry in
                let frame = geometry.frame(in: .local)
                return [frame.minX, frame.minY, frame.width, frame.height,
                 geometry.safeAreaInsets.top, geometry.safeAreaInsets.leading,
                 geometry.safeAreaInsets.bottom, geometry.safeAreaInsets.trailing]
            } action: { metrics in
                guard metrics.count == 8 else { return }
                let bounds = CGRect(x: metrics[0], y: metrics[1], width: metrics[2], height: metrics[3])
                mapViewportSafeInsets = Array(metrics[4...7])
                guard bounds != mapViewportLocalBounds else { return }
                mapViewportLocalBounds = bounds
                let size = bounds.size
                mapViewportSize = size
                scheduleCaptionLayoutRefresh(using: proxy)
                model.traceUIInteraction(
                    "people map local-clip=\(Int(bounds.minX.rounded())),\(Int(bounds.minY.rounded())) "
                        + "pt=\(Int(size.width.rounded()))x\(Int(size.height.rounded())) "
                        + "px=\(Int((size.width * displayScale).rounded()))x\(Int((size.height * displayScale).rounded())) "
                        + "safe=\(mapViewportSafeInsets.map { Int($0.rounded()) })"
                )
            }
            .onMapCameraChange(frequency: .continuous) { _ in
                guard position.positionedByUser else { return }
                invalidatePendingRecenter(reason: "user-map-gesture")
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                // positionedByUser remains true after the first pan. Check each
                // settled gesture so a later pan also invalidates a pending
                // Recenter request without affecting a new explicit Recenter.
                if position.positionedByUser {
                    invalidatePendingRecenter(reason: "user-map-gesture")
                }
                cameraSettledRevision &+= 1
                lastSettledCamera = context.camera
                let footprints = cameraFootprints(using: proxy)
                let projectedBounds = footprints.map { $0.frame(at: $0.point) }
                let targetPins = cameraTargetPins
                let cameraCenter = proxy.convert(context.camera.centerCoordinate, to: .local)
                let measuredSizes = targetPins.compactMap { mapAnnotationSizes[$0.id] }
                let footprintSummary: String
                if measuredSizes.isEmpty {
                    footprintSummary = "measured-footprints=0"
                } else {
                    let widths = measuredSizes.map(\.width)
                    let heights = measuredSizes.map(\.height)
                    footprintSummary = String(
                        format: "measured-footprints=%d width=%.1f...%.1f height=%.1f...%.1f",
                        measuredSizes.count,
                        widths.min() ?? 0,
                        widths.max() ?? 0,
                        heights.min() ?? 0,
                        heights.max() ?? 0
                    )
                }
                let distanceComparison: String
                if let requestedCameraDistance, requestedCameraDistance.isFinite, requestedCameraDistance > 0 {
                    if context.camera.distance < requestedCameraDistance * 0.98 {
                        cameraZoomOutWasClamped = true
                    }
                    distanceComparison = String(
                        format: "distance-request=%.1f distance-applied=%.1f ratio=%.3f",
                        requestedCameraDistance,
                        context.camera.distance,
                        context.camera.distance / requestedCameraDistance
                    )
                    self.requestedCameraDistance = nil
                } else {
                    distanceComparison = "distance-request=none"
                }
                let cameraComparison: String
                if let requestedMapRect, requestedMapRect.width > 0, requestedMapRect.height > 0 {
                    let normalizedX = (context.rect.midX - requestedMapRect.midX) / requestedMapRect.width
                    let normalizedY = (context.rect.midY - requestedMapRect.midY) / requestedMapRect.height
                    cameraComparison = String(
                        format: "camera-ratio=%.3f,%.3f center-norm=%.3f,%.3f center-px=%.1f,%.1f",
                        context.rect.width / requestedMapRect.width,
                        context.rect.height / requestedMapRect.height,
                        normalizedX,
                        normalizedY,
                        normalizedX * mapViewportSize.width * displayScale,
                        normalizedY * mapViewportSize.height * displayScale
                    )
                } else {
                    cameraComparison = "camera-request=none"
                }
                model.traceUIInteraction(
                    "people map anchors=\(anchorSummary(footprints)) viewport=\(Int(mapViewportSize.width.rounded()))x\(Int(mapViewportSize.height.rounded())) "
                        + "center=\(Int(cameraCenter?.x ?? -1)),\(Int(cameraCenter?.y ?? -1)) "
                        + "projected=\(projectedBounds.count)/\(targetPins.count) \(cameraComparison) \(distanceComparison) \(footprintSummary)"
                )
                scheduleCaptionLayoutRefresh(using: proxy)
                scheduleCameraBoundsCorrection(using: proxy)
            }
            .onChange(of: mapAnnotationSizes) { _, _ in
                scheduleCaptionLayoutRefresh(using: proxy)
                guard !userMovedMap, !position.positionedByUser else { return }
                scheduleCameraBoundsCorrection(using: proxy)
            }
            .onChange(of: mapCaptionSizes) { _, _ in
                scheduleCaptionLayoutRefresh(using: proxy)
                guard !userMovedMap, !position.positionedByUser else { return }
                resetCameraBoundsCorrection(preservingSettledCamera: true)
                scheduleCameraBoundsCorrection(using: proxy)
            }
            .onChange(of: displayedCaptionPlacements) { _, _ in
                guard !userMovedMap, !position.positionedByUser else { return }
                scheduleCameraBoundsCorrection(using: proxy)
            }
            .onChange(of: cameraCorrectionRequestToken) { _, _ in
                scheduleCameraBoundsCorrection(using: proxy)
            }
            .onAppear { scheduleCaptionLayoutRefresh(using: proxy) }
            .onDisappear {
                captionLayoutTask?.cancel()
                captionLayoutTask = nil
                captionLayoutGeneration &+= 1
                resetCameraBoundsCorrection()
            }
        }
    }

    private func activateMapPin(_ personID: UUID) {
        let member = model.member(personID)
        model.traceUIInteraction("people map pin activated memberFound=\(member != nil)")
        guard let member else { return }
        model.openView(member)
    }

    private var compactMapHeader: some View {
        HStack(spacing: 12) {
            mapTitle
            Spacer(minLength: 8)
            recenterButton
        }
        .padding(.horizontal, TrustTheme.gutter)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("people-map-header")
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { measuredHeight in
            guard abs(compactHeaderHeight - measuredHeight) > 1 else { return }
            compactHeaderHeight = measuredHeight
        }
    }

    private var mapTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            TrustPageTitle(text: TrustCopy.people, size: 24)
            Text(TrustCopy.onMap(count: pins.count, sealed: max(0, model.circle.count - pins.count)))
                .trustFont(12, weight: .medium)
                .foregroundStyle(palette.chromeMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            fallbackCameraTargetID = nil
            fallbackViewportAtFocus = nil
            cameraZoomOutWasClamped = false
            recenterIntentGeneration &+= 1
            let requestedGeneration = recenterIntentGeneration
            pendingRecenterGeneration = requestedGeneration
            model.requestMapRecenter {
                guard requestedGeneration == recenterIntentGeneration,
                      pendingRecenterGeneration == requestedGeneration else {
                    model.traceUIInteraction("people map recenter ignored after newer map intent")
                    return
                }
                // Consume this request before changing the camera so subsequent
                // map events cannot invalidate or replay the same completion.
                pendingRecenterGeneration = nil
                userMovedMap = false
                fitAll(includeUser: true)
            }
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
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
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
                        actionTitle: model.connectionRequests.incoming.isEmpty ? TrustCopy.addSomeone : TrustCopy.reviewRequests
                    ) {
                        if model.connectionRequests.incoming.isEmpty {
                            model.showingAddPersonSheet = true
                        } else {
                            model.selectedTab = .sharing
                        }
                    }
                    .padding(.horizontal, TrustTheme.gutter)
                    .padding(.bottom, listInset)
                }
                .refreshable {
                    await model.refresh()
                }
                .accessibilityIdentifier("people-list")
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
                                Button(model.connectionRequests.incoming.isEmpty ? TrustCopy.addSomeone : TrustCopy.reviewRequests) {
                                    if model.connectionRequests.incoming.isEmpty {
                                        model.showingAddPersonSheet = true
                                    } else {
                                        model.selectedTab = .sharing
                                    }
                                }
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
                    .refreshable {
                        await model.refresh()
                    }
                    .accessibilityIdentifier("people-list")
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
                withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
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
        withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
            sheetFraction = detents[next].rawValue
        }
    }

    private func toggleDetent() {
        let current = PeopleSheetDetent.nearest(to: sheetFraction)
        withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
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

    private var cameraTargetPins: [AppModel.MapPin] {
        if case let .view(personID)? = model.circlePath.last {
            return pins.filter { $0.id == personID }
        }
        if let fallbackCameraTargetID {
            return pins.filter { $0.id == fallbackCameraTargetID }
        }
        if let fix = model.location.lastFix {
            let nearbyPins = pins.filter {
                isAuthorizedPin($0, near: fix.coordinate)
            }
            if !nearbyPins.isEmpty { return nearbyPins }
            if isExplicitRecenterFit { return [] }
        }
        return pins
    }

    private func isAuthorizedPin(_ pin: AppModel.MapPin, near coordinate: CLLocationCoordinate2D) -> Bool {
        abs(pin.point.coordinate.latitude - coordinate.latitude) < 0.35
            && abs(pin.point.coordinate.longitude - coordinate.longitude) < 0.45
    }

    private func hasNearbyAuthorizedPinCluster(around coordinate: CLLocationCoordinate2D) -> Bool {
        pins.contains { isAuthorizedPin($0, near: coordinate) }
    }

    private func cameraFootprints(using proxy: MapProxy) -> [TrustMapAnnotationFootprint] {
        return cameraTargetPins.compactMap { pin in
            guard let point = proxy.convert(pin.point.coordinate, to: .local) else { return nil }
            let captionSize = pin.live ? mapCaptionSizes[pin.id] : nil
            let placement = displayedCaptionPlacements[pin.id] ?? .centeredBelow
            let stale = pin.live && LocationFreshness.status(timestamp: pin.point.timestamp, now: .now) == .stale
            return TrustMapCaptionLayout.footprint(
                point: point,
                anchor: .bottom,
                captionSize: captionSize,
                placement: placement,
                stale: stale
            )
        }
    }

    private func hasAuthorizedPinFootprint(in viewport: CGRect, using proxy: MapProxy) -> Bool {
        pins.contains { pin in
            guard let point = proxy.convert(pin.point.coordinate, to: .local) else { return false }
            let captionSize = pin.live ? mapCaptionSizes[pin.id] : nil
            let placement = displayedCaptionPlacements[pin.id] ?? .centeredBelow
            let stale = pin.live && LocationFreshness.status(timestamp: pin.point.timestamp, now: .now) == .stale
            let footprint = TrustMapCaptionLayout.footprint(
                point: point,
                anchor: .bottom,
                captionSize: captionSize,
                placement: placement,
                stale: stale
            )
            return footprint.frame(at: point).intersects(viewport)
        }
    }

    private func computeCaptionPlacements(using proxy: MapProxy) -> [UUID: TrustMapCaptionPlacement] {
        let projectedPins = pins.compactMap { pin -> (AppModel.MapPin, CGPoint)? in
            guard let point = proxy.convert(pin.point.coordinate, to: .local) else { return nil }
            return (pin, point)
        }
        let candidates = projectedPins.map { pin, point -> TrustMapCaptionCandidate? in
            guard pin.live, let size = mapCaptionSizes[pin.id] else { return nil }
            return TrustMapCaptionCandidate(point: point, size: size, anchor: .bottom)
        }
        let discs = projectedPins.map { pin, point in
            let captionSize = pin.live ? mapCaptionSizes[pin.id] : nil
            let stale = pin.live && LocationFreshness.status(timestamp: pin.point.timestamp, now: .now) == .stale
            return TrustMapCaptionLayout.discBounds(point: point, anchor: .bottom, captionSize: captionSize, stale: stale)
        }
        let placements = TrustMapCaptionLayout.placements(
            candidates: candidates,
            discBounds: discs,
            viewport: mapViewportLocalBounds
        )
        return Dictionary(uniqueKeysWithValues: projectedPins.indices.compactMap { index in
            guard let placement = placements[index] else { return nil }
            return (projectedPins[index].0.id, placement)
        })
    }

    private func scheduleCaptionLayoutRefresh(using proxy: MapProxy) {
        captionLayoutTask?.cancel()
        captionLayoutGeneration &+= 1
        let generation = captionLayoutGeneration
        // MapProxy is a SwiftUI environment value whose lifetime is scoped to
        // this MapReader update. Resolve it before suspending; retaining it in a
        // Task can outlive a map re-layout (notably when Stage Manager resizes).
        let updated = computeCaptionPlacements(using: proxy)
        captionLayoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled, generation == captionLayoutGeneration else { return }
            guard updated != displayedCaptionPlacements else { return }
            displayedCaptionPlacements = updated
            let measuredCount = pins.filter { $0.live && mapCaptionSizes[$0.id] != nil }.count
            if measuredCount > updated.count {
                model.traceUIInteraction("people map caption placement unresolved count=\(measuredCount - updated.count)")
            }
            let aboveCount = updated.values.filter { $0.side == .above }.count
            let offsets = updated.values.map { abs($0.horizontalOffset) }
            model.traceUIInteraction(
                "people map caption layout applied count=\(updated.count) above=\(aboveCount) "
                    + "max-inward-offset=\(Int((offsets.max() ?? 0).rounded()))"
            )
        }
    }

    private func anchorSummary(_ footprints: [TrustMapAnnotationFootprint]) -> String {
        footprints.map { "\(Int($0.point.x.rounded())),\(Int($0.point.y.rounded()))" }.joined(separator: ";")
    }

    private func scheduleCameraBoundsCorrection(using proxy: MapProxy) {
        guard !userMovedMap, !position.positionedByUser, lastSettledCamera != nil else { return }
        cameraCorrectionTask?.cancel()
        let generation = cameraFitGeneration
        guard let camera = lastSettledCamera,
              let cameraCenter = proxy.convert(camera.centerCoordinate, to: .local),
              let correction = TrustMapCameraBounds.correction(
                footprints: cameraFootprints(using: proxy),
                cameraCenter: cameraCenter,
                usableViewport: mapViewportLocalBounds
              ) else { return }
        if let pendingCameraCorrectionOverflow {
            // Only judge whether a correction helped after MapKit reports a
            // newer settled camera. Measurement callbacks can run against the
            // pre-correction camera while the 120ms update is still pending.
            guard cameraSettledRevision > cameraCorrectionAppliedRevision else { return }
            if correction.overflow <= 0.5 {
                self.pendingCameraCorrectionOverflow = nil
                model.traceUIInteraction("people map annotation bounds contained")
                return
            }
            guard correction.overflow < pendingCameraCorrectionOverflow - 0.5 else {
                self.pendingCameraCorrectionOverflow = nil
                cameraCorrectionAttempts = 3
                if isAutomaticPeopleFit,
                   cameraZoomOutWasClamped,
                   mapViewportLocalBounds.width > 1,
                   mapViewportLocalBounds.height > 1,
                   !hasAuthorizedPinFootprint(in: mapViewportLocalBounds, using: proxy),
                   model.location.lastFix.map({ !hasNearbyAuthorizedPinCluster(around: $0.coordinate) }) ?? true,
                   let target = pins.first {
                    fallbackCameraTargetID = target.id
                    fallbackViewportAtFocus = mapViewportSize
                    model.traceUIInteraction(
                        "people map bounded fallback focus=first-authorized reason=native-zoom-cap-and-no-visible-pin"
                    )
                    focusMap(on: target.id)
                    return
                }
                model.traceUIInteraction("people map annotation correction stopped without improvement")
                return
            }
            self.pendingCameraCorrectionOverflow = nil
        }
        guard correction.isNeeded, cameraCorrectionAttempts < 3 else { return }
        let adjustedCenterPoint = CGPoint(
            x: cameraCenter.x - correction.translation.x * correction.scale,
            y: cameraCenter.y - correction.translation.y * correction.scale
        )
        guard let adjustedCenter = proxy.convert(adjustedCenterPoint, from: .local),
              adjustedCenter.latitude.isFinite, adjustedCenter.longitude.isFinite,
              camera.distance.isFinite, camera.heading.isFinite, camera.pitch.isFinite else { return }
        let distance = camera.distance * Double(correction.scale)
        guard distance.isFinite, distance > 0 else { return }
        // Capture only value types for the delayed task. Never retain `proxy`
        // across Task.sleep: MapReader can be replaced before the task resumes.
        let correctedCamera = MapCamera(
            centerCoordinate: adjustedCenter,
            distance: distance,
            heading: camera.heading,
            pitch: camera.pitch
        )
        let overflow = correction.overflow
        let scale = correction.scale
        let translation = correction.translation
        let scheduledCameraRevision = cameraSettledRevision
        cameraCorrectionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  generation == cameraFitGeneration,
                  !userMovedMap, !position.positionedByUser,
                  lastSettledCamera != nil,
                  cameraSettledRevision == scheduledCameraRevision else { return }
            pendingCameraCorrectionOverflow = overflow
            cameraCorrectionAttempts += 1
            cameraCorrectionAppliedRevision = scheduledCameraRevision
            requestedCameraDistance = distance
            position = .camera(correctedCamera)
            model.traceUIInteraction(
                "people map annotation correction scale=\(String(format: "%.3f", scale)) "
                    + "translation=\(Int(translation.x.rounded())),\(Int(translation.y.rounded())) attempt=\(cameraCorrectionAttempts)"
            )
        }
    }

    private func resetCameraBoundsCorrection(preservingSettledCamera: Bool = false) {
        cameraCorrectionTask?.cancel()
        cameraCorrectionTask = nil
        cameraFitGeneration &+= 1
        cameraCorrectionAttempts = 0
        pendingCameraCorrectionOverflow = nil
        cameraCorrectionAppliedRevision = cameraSettledRevision
        if !preservingSettledCamera { cameraZoomOutWasClamped = false }
        if !preservingSettledCamera { lastSettledCamera = nil }
    }

    private func fitAll(includeUser: Bool = false, animated: Bool = true) {
        // GPS-backed Recenter includes this device and excludes the bounded People
        // fallback. If no own fix exists to include, retain the ordinary fit fallback.
        isAutomaticPeopleFit = !includeUser || model.location.lastFix == nil
        isExplicitRecenterFit = includeUser && model.location.lastFix != nil
        var coordinates = pins.map(\.point.coordinate)
        if includeUser, let fix = model.location.lastFix {
            coordinates.append(fix.coordinate)
        }
        withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.35) : nil) {
            if model.location.lastFix == nil {
                let alreadyAutomatic = usesNativeAutomaticFit
                resetCameraBoundsCorrection(preservingSettledCamera: alreadyAutomatic)
                requestedMapRect = nil
                usesNativeAutomaticFit = true
                position = .automatic
                model.traceUIInteraction("people map native automatic fit applied")
                if alreadyAutomatic, lastSettledCamera != nil {
                    cameraCorrectionRequestToken &+= 1
                }
                return
            }
            if let region = metroRegion(for: coordinates) {
                setCamera(to: region)
            } else {
                resetCameraBoundsCorrection()
                requestedMapRect = nil
                usesNativeAutomaticFit = true
                position = .automatic
            }
        }
    }

    private func invalidatePendingRecenter(reason: String) {
        guard pendingRecenterGeneration != nil else { return }
        recenterIntentGeneration &+= 1
        pendingRecenterGeneration = nil
        model.traceUIInteraction("people map recenter intent invalidated reason=\(reason)")
    }

    private func focusMap(on personID: UUID, animated: Bool = true) {
        isAutomaticPeopleFit = false
        isExplicitRecenterFit = false
        guard let point = pins.first(where: { $0.id == personID })?.point else { return }
        let region = MKCoordinateRegion(
            center: point.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
        withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.35) : nil) {
            setCamera(to: region)
        }
    }

    private func setCamera(to region: MKCoordinateRegion) {
        resetCameraBoundsCorrection()
        usesNativeAutomaticFit = false
        guard mapViewportSize.width > 1, mapViewportSize.height > 1 else {
            requestedMapRect = nil
            position = .region(region)
            return
        }
        let rect = mapRect(for: region, viewport: mapViewportSize)
        requestedMapRect = rect
        position = .region(MKCoordinateRegion(rect))
        model.traceUIInteraction("people map camera fit applied=true")
    }

    private func scheduleViewportCameraFit() {
        mapViewportFitTask?.cancel()
        mapViewportFitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled,
                  mapViewportSize.width > 0,
                  mapViewportSize.height > 0 else { return }
            model.traceUIInteraction("people map viewport usable=true")
            fitOrFocusSelectedView()
        }
    }

    private func mapRect(for region: MKCoordinateRegion, viewport: CGSize) -> MKMapRect {
        let latitudeLimit = 85.05112878
        let northLatitude = min(latitudeLimit, region.center.latitude + region.span.latitudeDelta / 2)
        let southLatitude = max(-latitudeLimit, region.center.latitude - region.span.latitudeDelta / 2)
        let westLongitude = region.center.longitude - region.span.longitudeDelta / 2
        let eastLongitude = region.center.longitude + region.span.longitudeDelta / 2
        let north = MKMapPoint(CLLocationCoordinate2D(latitude: northLatitude, longitude: westLongitude))
        let south = MKMapPoint(CLLocationCoordinate2D(latitude: southLatitude, longitude: eastLongitude))
        let base = MKMapRect(
            x: min(north.x, south.x),
            y: min(north.y, south.y),
            width: max(1, abs(south.x - north.x)),
            height: max(1, abs(south.y - north.y))
        )

        // Live freshness capsules are wider than the 44pt pin target. Reserve room
        // for their full localized width as well as the marker disc.
        let sideInset: CGFloat = 64
        let topInset: CGFloat = 64
        let bottomInset: CGFloat = 36
        let availableWidth = max(1, Double(viewport.width - sideInset * 2))
        let availableHeight = max(1, Double(viewport.height - topInset - bottomInset))
        let mapPointsPerScreenPoint = max(base.width / availableWidth, base.height / availableHeight)
        let cameraWidth = Double(viewport.width) * mapPointsPerScreenPoint
        let cameraHeight = Double(viewport.height) * mapPointsPerScreenPoint
        let shiftedCenterY = base.midY - mapPointsPerScreenPoint * Double((topInset - bottomInset) / 2)
        return MKMapRect(
            x: base.midX - cameraWidth / 2,
            y: shiftedCenterY - cameraHeight / 2,
            width: cameraWidth,
            height: cameraHeight
        )
    }

    private func fitOrFocusSelectedView(animated: Bool = true) {
        guard !userMovedMap else { return }
        if case let .view(personID)? = model.circlePath.last,
           pins.contains(where: { $0.id == personID }) {
            focusMap(on: personID, animated: animated)
        } else if let fallbackCameraTargetID,
                  pins.contains(where: { $0.id == fallbackCameraTargetID }) {
            focusMap(on: fallbackCameraTargetID, animated: animated)
        } else {
            fitAll(animated: animated)
        }
    }

    private var isShowingSpecificPersonView: Bool {
        guard let route = model.circlePath.last else { return false }
        if case .view = route { return true }
        return false
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
            latitudeDelta: min(maxLatitudeSpan, max(maxLat - minLat, 0.045)),
            longitudeDelta: min(maxLongitudeSpan, max(maxLon - minLon, 0.045))
        )
        return MKCoordinateRegion(center: center, span: span)
    }

}

private struct CircleMapPinLocation: Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double

    init(_ pin: AppModel.MapPin) {
        id = pin.id
        latitude = pin.point.coordinate.latitude
        longitude = pin.point.coordinate.longitude
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
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let status = statusText(at: context.date)
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
                        if let status {
                            Text(status)
                                .trustFont(13)
                                .foregroundStyle(palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(status.map { "\(member.person.displayName). \($0)" } ?? member.person.displayName)
            .accessibilityIdentifier("person-row-\(member.firstName.lowercased())")
        }
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
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 14)
                .frame(minWidth: 66, minHeight: 44)
                .background {
                    Capsule()
                        .fill(peekIsLook ? palette.accentSoft : palette.surface)
                        .overlay {
                            Capsule()
                                .stroke(peekIsLook ? palette.accentSoft : palette.accent.opacity(0.42), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(peekIsLook ? TrustCopy.lookHint(name: member.firstName) : TrustCopy.viewHint(name: member.firstName))
        .accessibilityIdentifier("person-peek-\(member.firstName.lowercased())")
    }

    private func statusText(at now: Date) -> String? {
        if member.isAvailable {
            guard member.liveAccessIsCurrent else { return TrustCopy.locationUnavailable }
            return TrustCopy.authorizedLiveLocationStatus(
                timestamp: member.currentLivePoint?.timestamp,
                now: now,
                presence: member.visiblePresence?.label
            )
        }
        if member.isPaused { return TrustCopy.pause }
        if isNotSharing { return TrustCopy.choseOff(name: member.firstName) }
        return member.visiblePresence?.label
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let status = statusText(member) {
                Text(status)
                    .trustFont(17)
                    .foregroundStyle(palette.muted)
                    .accessibilityIdentifier("person-status")
            }
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
                        if let status = statusText(member) {
                            Text(status)
                                .trustFont(15)
                                .foregroundStyle(palette.muted)
                        }
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
                        Text(TrustCopy.formattedDateTime(visit.at, dateStyle: .abbreviated, timeStyle: .shortened))
                            .trustFont(13)
                            .foregroundStyle(palette.muted)
                    }
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("person-history-visit-\(index)")
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

    private func statusText(_ member: TrustedPerson) -> String? {
        if member.isPaused { return TrustCopy.pause }
        if member.isNotSharingWithYou { return TrustCopy.choseOff(name: member.firstName) }
        return member.visiblePresence?.label
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
