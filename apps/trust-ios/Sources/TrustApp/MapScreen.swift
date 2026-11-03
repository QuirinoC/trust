import MapKit
import SwiftUI
import TrustCore

private struct MapCanvasViewport: Equatable {
    let bounds: CGRect
    let safeInsets: [CGFloat]
}

private struct MapCanvasMeasurements {
    var annotationSizes: [UUID: CGSize] = [:]
    var captionSizes: [UUID: CGSize] = [:]
}

private struct MapCanvasOwner<Content: View>: View {
    @State private var ownerID = UUID()
    private let content: (UUID) -> Content

    init(@ViewBuilder content: @escaping (UUID) -> Content) {
        self.content = content
    }

    var body: some View {
        content(ownerID)
    }
}

/// D2 Map — secondary push from View. Confirmed Look snapshots and server-authorized
/// live pins appear here; a Sealed person without a recorded snapshot has no pin.
/// Regular width: full-bleed map + trailing panel.
struct MapScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedID: UUID?
    @State private var mapViewportSize: CGSize = .zero
    @State private var mapViewportLocalBounds: CGRect = .zero
    @State private var mapViewportSafeInsets: [CGFloat] = [0, 0, 0, 0]
    @State private var activeMapCanvasOwner: UUID?
    @State private var mapCanvasViewports: [UUID: MapCanvasViewport] = [:]
    @State private var mapCanvasMeasurements: [UUID: MapCanvasMeasurements] = [:]
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
    @State private var cameraSettledRevision = 0
    @State private var cameraCorrectionAppliedRevision = -1
    @State private var cameraFitGeneration = 0
    @State private var cameraCorrectionTask: Task<Void, Never>?
    @State private var cameraCorrectionRequestToken = 0
    @State private var usesNativeAutomaticFit = false
    @State private var userMovedMap = false

    private var pins: [AppModel.MapPin] { model.homeMapPins }
    private var sealedCount: Int { max(0, model.circle.count - pins.count) }
    private var focusedPersonUnavailable: Bool {
        switch model.mapFocus {
        case .person(let id): !pins.contains(where: { $0.id == id })
        case .automatic: false
        }
    }
    private var selected: AppModel.MapPin? {
        switch model.mapFocus {
        case .automatic:
            return pins.first { $0.id == selectedID } ?? pins.first
        case .person(let id):
            return pins.first { $0.id == id }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let isWide = width >= 650
            let panelWidth = min(390, max(330, width * 0.36))
            Group {
                if pins.isEmpty {
                    TrustEmptyState(
                        glyph: "lock",
                        title: TrustCopy.noLocationsYet,
                        message: focusedPersonUnavailable ? TrustCopy.mapFocusUnavailable : TrustCopy.mapEmptyBody,
                        actionTitle: TrustCopy.backToCircle
                    ) {
                        model.circlePath = []
                    }
                } else if isWide {
                    regularContent(panelWidth: panelWidth)
                } else {
                    compactContent(availableHeight: geometry.size.height)
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
            switch model.mapFocus {
            case .person(let requestedID):
                if pins.contains(where: { $0.id == requestedID }) {
                    selectedID = requestedID
                } else {
                    // Keep other authorized pins visible without implying one
                    // belongs to the person whose location was requested. Retain
                    // the UUID so focus can recover if an eligible pin returns.
                    selectedID = nil
                }
            case .automatic:
                if let remembered = model.mapSelectedPersonID,
                   pins.contains(where: { $0.id == remembered }) {
                    selectedID = remembered
                } else {
                    selectedID = nil
                }
            }
            fitAll()
        }
        .onChange(of: selectedID) { _, newValue in
            guard let newValue, pins.contains(where: { $0.id == newValue }) else { return }
            model.selectMapPerson(newValue)
        }
        .onChange(of: pins.map(\.id)) { _, ids in
            resetCameraBoundsCorrection(preservingSettledCamera: usesNativeAutomaticFit)
            if case .person(let focusedID) = model.mapFocus {
                selectedID = ids.contains(focusedID) ? focusedID : nil
            }
            fitAll()
        }
        .onChange(of: mapViewportLocalBounds) { _, bounds in
            resetCameraBoundsCorrection(preservingSettledCamera: usesNativeAutomaticFit)
            guard bounds.width > 0, bounds.height > 0, !userMovedMap else { return }
            fitAll()
        }
        .onChange(of: position.positionedByUser) { _, movedByUser in
            if movedByUser {
                userMovedMap = true
                usesNativeAutomaticFit = false
                resetCameraBoundsCorrection()
            }
        }
        .onDisappear {
            captionLayoutTask?.cancel()
            captionLayoutTask = nil
            captionLayoutGeneration &+= 1
            activeMapCanvasOwner = nil
            resetCameraBoundsCorrection()
        }
    }

    /// iPad regular width: full-bleed map + trailing person panel. Compact (iPhone and
    /// Split View / Stage Manager narrow) stays stacked.
    private func regularContent(panelWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            MapCanvasOwner { ownerID in
                mapCanvas(ownerID: ownerID)
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .trailing) { palette.line.frame(width: 1) }
            ScrollView { personPanel(isWide: true) }
                .frame(width: panelWidth)
                .background(palette.paper)
        }
    }

    private func compactContent(availableHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                mapHeader
                    .padding(.horizontal, TrustTheme.gutter)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                MapCanvasOwner { ownerID in
                    mapCanvas(ownerID: ownerID)
                }
                    .frame(height: min(320, max(200, availableHeight * 0.42)))
                personPanel(isWide: false)
            }
            .padding(.bottom, 16)
        }
    }

    private var mapHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            TrustPageTitle(text: TrustCopy.map)
            Text(TrustCopy.onMap(count: pins.count, sealed: sealedCount))
                .trustFont(12)
                .foregroundStyle(palette.muted)
        }
    }

    private func mapCanvas(ownerID: UUID) -> some View {
        MapReader { proxy in
            let captionLayout = displayedCaptionPlacements
            Map(position: mapPositionBinding(ownerID), selection: selectedIDBinding(ownerID)) {
                ForEach(pins) { pin in
                    let captionSize = pin.live ? mapCaptionSizes[pin.id] : nil
                    let placement = captionLayout[pin.id] ?? .centeredBelow
                    let stale = pin.live && LocationFreshness.status(timestamp: pin.point.timestamp, now: .now) == .stale
                    let pinLayout: TrustMapPinGeometryLayout? = pin.live && captionSize == nil
                        ? nil
                        : TrustMapCaptionLayout.pinGeometry(
                            anchor: .center,
                            captionSize: captionSize,
                            placement: placement,
                            stale: stale,
                            minimumFrame: CGSize(width: 44, height: 44)
                        )
                    let annotationAnchor = pinLayout.map {
                        UnitPoint(x: $0.annotationAnchor.x, y: $0.annotationAnchor.y)
                    } ?? .center
                    Annotation(pin.name, coordinate: pin.point.coordinate, anchor: annotationAnchor) {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            TrustMapPin(
                                initials: pin.name.trustInitials,
                                live: pin.live,
                                selected: selected?.id == pin.id,
                                stale: pin.live && LocationFreshness.status(timestamp: pin.point.timestamp, now: context.date) == .stale,
                                ageCaption: pin.live ? TrustCopy.locationAgeCaption(timestamp: pin.point.timestamp, now: context.date) : nil,
                                pinLayout: pinLayout,
                                onCaptionSizeChange: { size in
                                    guard size.width > 0, size.height > 0 else { return }
                                    var measurements = mapCanvasMeasurements[ownerID] ?? MapCanvasMeasurements()
                                    measurements.captionSizes[pin.id] = size
                                    mapCanvasMeasurements[ownerID] = measurements
                                    guard activeMapCanvasOwner == ownerID,
                                          mapCaptionSizes[pin.id] != size else { return }
                                    mapCaptionSizes[pin.id] = size
                                }
                            )
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                                guard size.width > 0, size.height > 0 else { return }
                                var measurements = mapCanvasMeasurements[ownerID] ?? MapCanvasMeasurements()
                                measurements.annotationSizes[pin.id] = size
                                mapCanvasMeasurements[ownerID] = measurements
                                guard activeMapCanvasOwner == ownerID,
                                      mapAnnotationSizes[pin.id] != size else { return }
                                mapAnnotationSizes[pin.id] = size
                            }
                            .onTapGesture {
                                guard activeMapCanvasOwner == ownerID else { return }
                                selectPerson(pin.id)
                            }
                            .accessibilityLabel(TrustCopy.pinAccessibility(name: pin.name, live: pin.live, timestamp: pin.point.timestamp, now: context.date))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAddTraits(selected?.id == pin.id ? [.isSelected] : [])
                        }
                    }
                    .annotationTitles(.hidden)
                    .tag(pin.id)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass() }
            .accessibilityLabel(TrustCopy.mapAccessibility)
            .accessibilityIdentifier("map-screen-canvas")
            .onGeometryChange(for: [CGFloat].self) { geometry in
                let frame = geometry.frame(in: .local)
                return [frame.minX, frame.minY, frame.width, frame.height,
                 geometry.safeAreaInsets.top, geometry.safeAreaInsets.leading,
                 geometry.safeAreaInsets.bottom, geometry.safeAreaInsets.trailing]
            } action: { metrics in
                guard metrics.count == 8 else { return }
                let bounds = CGRect(x: metrics[0], y: metrics[1], width: metrics[2], height: metrics[3])
                let viewport = MapCanvasViewport(bounds: bounds, safeInsets: Array(metrics[4...7]))
                mapCanvasViewports[ownerID] = viewport
                guard activeMapCanvasOwner == ownerID else { return }
                guard applyMapCanvasViewport(viewport, ownerID: ownerID) else { return }
                let size = bounds.size
                scheduleCaptionLayoutRefresh(using: proxy, ownerID: ownerID)
                model.traceUIInteraction(
                    "map route local-clip=\(Int(bounds.minX.rounded())),\(Int(bounds.minY.rounded())) "
                        + "pt=\(Int(size.width.rounded()))x\(Int(size.height.rounded())) "
                        + "px=\(Int((size.width * displayScale).rounded()))x\(Int((size.height * displayScale).rounded())) "
                        + "safe=\(mapViewportSafeInsets.map { Int($0.rounded()) })"
                )
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                guard activeMapCanvasOwner == ownerID else { return }
                cameraSettledRevision &+= 1
                lastSettledCamera = context.camera
                let footprints = cameraFootprints(using: proxy)
                let projectedBounds = footprints.map { $0.frame(at: $0.point) }
                let targetPins = cameraTargetPins
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
                let cameraCenter = proxy.convert(context.camera.centerCoordinate, to: .local)
                model.traceUIInteraction(
                    "map route anchors=\(anchorSummary(footprints)) viewport=\(Int(mapViewportSize.width.rounded()))x\(Int(mapViewportSize.height.rounded())) "
                        + "center=\(Int(cameraCenter?.x ?? -1)),\(Int(cameraCenter?.y ?? -1)) "
                        + "projected=\(projectedBounds.count)/\(targetPins.count) \(cameraComparison) \(distanceComparison) \(footprintSummary)"
                )
                scheduleCaptionLayoutRefresh(using: proxy, ownerID: ownerID)
                scheduleCameraBoundsCorrection(using: proxy, ownerID: ownerID)
            }
            .onChange(of: mapAnnotationSizes) { _, _ in
                guard activeMapCanvasOwner == ownerID else { return }
                scheduleCaptionLayoutRefresh(using: proxy, ownerID: ownerID)
                guard !userMovedMap, !position.positionedByUser else { return }
                scheduleCameraBoundsCorrection(using: proxy, ownerID: ownerID)
            }
            .onChange(of: mapCaptionSizes) { _, _ in
                guard activeMapCanvasOwner == ownerID else { return }
                scheduleCaptionLayoutRefresh(using: proxy, ownerID: ownerID)
                guard !userMovedMap, !position.positionedByUser else { return }
                resetCameraBoundsCorrection(preservingSettledCamera: true)
                scheduleCameraBoundsCorrection(using: proxy, ownerID: ownerID)
            }
            .onChange(of: displayedCaptionPlacements) { _, _ in
                guard activeMapCanvasOwner == ownerID else { return }
                guard !userMovedMap, !position.positionedByUser else { return }
                scheduleCameraBoundsCorrection(using: proxy, ownerID: ownerID)
            }
            .onChange(of: cameraCorrectionRequestToken) { _, _ in
                guard activeMapCanvasOwner == ownerID else { return }
                scheduleCameraBoundsCorrection(using: proxy, ownerID: ownerID)
            }
            .onAppear {
                claimMapCanvas(ownerID)
                scheduleCaptionLayoutRefresh(using: proxy, ownerID: ownerID)
            }
            .onDisappear {
                mapCanvasViewports.removeValue(forKey: ownerID)
                mapCanvasMeasurements.removeValue(forKey: ownerID)
                guard activeMapCanvasOwner == ownerID else { return }
                activeMapCanvasOwner = nil
                captionLayoutTask?.cancel()
                captionLayoutTask = nil
                captionLayoutGeneration &+= 1
                resetCameraBoundsCorrection()
            }
        }
    }

    private func personPanel(isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isWide {
                mapHeader
                    .padding(.horizontal, TrustTheme.gutter)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
            }
            if pins.contains(where: \.live) && pins.contains(where: { !$0.live }) {
                HStack(spacing: 14) {
                    mapLegend(color: palette.pinLive, title: TrustCopy.always)
                    mapLegend(color: palette.pinLook, title: TrustCopy.snapshot)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, TrustTheme.gutter)
                .padding(.vertical, 10)
            }

            if focusedPersonUnavailable {
                Text(TrustCopy.mapFocusUnavailable)
                    .trustFont(12)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("map-focus-unavailable")
                    .padding(.horizontal, TrustTheme.gutter)
                    .padding(.bottom, 10)
            }

            if let selected, let member = model.member(selected.id) {
                personCard(selected, member)
            }

            if pins.count > 1 || (pins.count == 1 && focusedPersonUnavailable) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pins) { pin in
                            Button(pin.name.trustFirstName) { selectPerson(pin.id) }
                                .trustFont(13, weight: .medium)
                                .foregroundStyle(selected?.id == pin.id ? palette.paper : palette.ink)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(selected?.id == pin.id ? palette.ink : palette.surface))
                                .accessibilityLabel(TrustCopy.showOnMap(name: pin.name))
                                .accessibilityAddTraits(selected?.id == pin.id ? [.isSelected] : [])
                        }
                    }
                    .padding(.horizontal, TrustTheme.gutter)
                }
                .padding(.bottom, 12)
            }

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
                .accessibilityIdentifier("map-view-selected-person")
                .padding(.horizontal, TrustTheme.gutter)
            }

            if sealedCount > 0 {
                TrustFootnote(glyph: "lock", text: TrustCopy.sealedNotOnMap(sealedCount))
                    .padding(.horizontal, TrustTheme.gutter)
                    .padding(.top, 10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map-screen-person-panel")
    }

    private func personCard(_ pin: AppModel.MapPin, _ member: TrustedPerson) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                TrustAvatar(name: member.person.displayName, seed: model.circle.firstIndex { $0.id == member.id } ?? 0, size: 40, avatar: member.person.avatar, personID: member.id)
                Text(member.person.displayName)
                    .trustFont(15, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("map-selected-person-name")
                Spacer()
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(subtitle(pin, member, now: context.date))
                    .trustFont(12)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("map-selected-location-time")
            }

        }
        .padding(.horizontal, TrustTheme.gutter)
        .padding(.bottom, 12)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selectedID)
        .accessibilityElement(children: .combine)
    }

    private func mapLegend(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).trustFont(11, weight: .medium).foregroundStyle(palette.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private func selectPerson(_ id: UUID) {
        guard selected?.id != id else { return }
        model.selectMapPerson(id)
        if reduceMotion {
            selectedID = id
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { selectedID = id }
        }
    }

    private func mapPositionBinding(_ ownerID: UUID) -> Binding<MapCameraPosition> {
        Binding(
            get: { position },
            set: { newPosition in
                guard activeMapCanvasOwner == ownerID else { return }
                position = newPosition
            }
        )
    }

    private func selectedIDBinding(_ ownerID: UUID) -> Binding<UUID?> {
        Binding(
            get: { selectedID },
            set: { newValue in
                guard activeMapCanvasOwner == ownerID else { return }
                selectedID = newValue
            }
        )
    }

    private func subtitle(_ pin: AppModel.MapPin, _ member: TrustedPerson, now: Date) -> String {
        let time = TrustCopy.formattedDateTime(pin.point.timestamp, dateStyle: .abbreviated, timeStyle: .shortened)
        let locationStatus = pin.live
            ? "\(TrustCopy.always) · \(TrustCopy.locationFreshness(timestamp: pin.point.timestamp, now: now))"
            : TrustCopy.snapshotAt(time)
        guard let presence = member.visiblePresence?.label else { return locationStatus }
        return "\(locationStatus) · \(presence)"
    }

    private var cameraTargetPins: [AppModel.MapPin] {
        pins
    }

    private func cameraFootprints(using proxy: MapProxy) -> [TrustMapAnnotationFootprint] {
        return cameraTargetPins.compactMap { pin in
            guard let point = proxy.convert(pin.point.coordinate, to: .local) else { return nil }
            let captionSize = pin.live ? mapCaptionSizes[pin.id] : nil
            let placement = displayedCaptionPlacements[pin.id] ?? .centeredBelow
            let stale = pin.live && LocationFreshness.status(timestamp: pin.point.timestamp, now: .now) == .stale
            return TrustMapCaptionLayout.footprint(
                point: point,
                anchor: .center,
                captionSize: captionSize,
                placement: placement,
                stale: stale
            )
        }
    }

    private func computeCaptionPlacements(using proxy: MapProxy) -> [UUID: TrustMapCaptionPlacement] {
        let projectedPins = pins.compactMap { pin -> (AppModel.MapPin, CGPoint)? in
            guard let point = proxy.convert(pin.point.coordinate, to: .local) else { return nil }
            return (pin, point)
        }
        let candidates = projectedPins.map { pin, point -> TrustMapCaptionCandidate? in
            guard pin.live, let size = mapCaptionSizes[pin.id] else { return nil }
            return TrustMapCaptionCandidate(point: point, size: size, anchor: .center)
        }
        let discs = projectedPins.map { pin, point in
            let captionSize = pin.live ? mapCaptionSizes[pin.id] : nil
            let stale = pin.live && LocationFreshness.status(timestamp: pin.point.timestamp, now: .now) == .stale
            return TrustMapCaptionLayout.discBounds(point: point, anchor: .center, captionSize: captionSize, stale: stale)
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

    private func claimMapCanvas(_ ownerID: UUID) {
        guard activeMapCanvasOwner != ownerID else { return }
        activeMapCanvasOwner = ownerID
        captionLayoutTask?.cancel()
        captionLayoutTask = nil
        captionLayoutGeneration &+= 1
        resetCameraBoundsCorrection()
        mapViewportLocalBounds = .zero
        mapViewportSize = .zero
        mapViewportSafeInsets = [0, 0, 0, 0]
        if let measurements = mapCanvasMeasurements[ownerID] {
            for (id, size) in measurements.annotationSizes {
                mapAnnotationSizes[id] = size
            }
            for (id, size) in measurements.captionSizes {
                mapCaptionSizes[id] = size
            }
        }
        if let viewport = mapCanvasViewports[ownerID] {
            _ = applyMapCanvasViewport(viewport, ownerID: ownerID)
        }
    }

    @discardableResult
    private func applyMapCanvasViewport(_ viewport: MapCanvasViewport, ownerID: UUID) -> Bool {
        guard activeMapCanvasOwner == ownerID else { return false }
        mapViewportSafeInsets = viewport.safeInsets
        guard viewport.bounds.width > 0, viewport.bounds.height > 0,
              viewport.bounds != mapViewportLocalBounds else { return false }
        mapViewportLocalBounds = viewport.bounds
        mapViewportSize = viewport.bounds.size
        return true
    }

    private func scheduleCaptionLayoutRefresh(using proxy: MapProxy, ownerID: UUID) {
        guard activeMapCanvasOwner == ownerID else { return }
        captionLayoutTask?.cancel()
        captionLayoutGeneration &+= 1
        let generation = captionLayoutGeneration
        // Resolve the SwiftUI MapProxy while this MapReader update is active.
        // Its lifetime may end while the delayed state update is suspended.
        let updated = computeCaptionPlacements(using: proxy)
        captionLayoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  generation == captionLayoutGeneration,
                  activeMapCanvasOwner == ownerID else { return }
            guard updated != displayedCaptionPlacements else { return }
            displayedCaptionPlacements = updated
            let measuredCount = pins.filter { $0.live && mapCaptionSizes[$0.id] != nil }.count
            if measuredCount > updated.count {
                model.traceUIInteraction("map route caption placement unresolved count=\(measuredCount - updated.count)")
            }
            let aboveCount = updated.values.filter { $0.side == .above }.count
            let offsets = updated.values.map { abs($0.horizontalOffset) }
            model.traceUIInteraction(
                "map route caption layout applied count=\(updated.count) above=\(aboveCount) "
                    + "max-inward-offset=\(Int((offsets.max() ?? 0).rounded()))"
            )
        }
    }

    private func anchorSummary(_ footprints: [TrustMapAnnotationFootprint]) -> String {
        footprints.map { "\(Int($0.point.x.rounded())),\(Int($0.point.y.rounded()))" }.joined(separator: ";")
    }

    private func scheduleCameraBoundsCorrection(using proxy: MapProxy, ownerID: UUID) {
        guard activeMapCanvasOwner == ownerID,
              !userMovedMap, !position.positionedByUser, lastSettledCamera != nil else { return }
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
            // Only judge correction progress after a newer settled camera;
            // layout callbacks may still describe the old camera meanwhile.
            guard cameraSettledRevision > cameraCorrectionAppliedRevision else { return }
            if correction.overflow <= 0.5 {
                self.pendingCameraCorrectionOverflow = nil
                model.traceUIInteraction("map route annotation bounds contained")
                return
            }
            guard correction.overflow < pendingCameraCorrectionOverflow - 0.5 else {
                self.pendingCameraCorrectionOverflow = nil
                cameraCorrectionAttempts = 3
                model.traceUIInteraction("map route annotation correction stopped without improvement")
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
        // Keep the delayed task value-only; do not carry MapProxy past sleep.
        cameraCorrectionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  generation == cameraFitGeneration,
                  activeMapCanvasOwner == ownerID,
                  !userMovedMap, !position.positionedByUser,
                  lastSettledCamera != nil,
                  cameraSettledRevision == scheduledCameraRevision else { return }
            pendingCameraCorrectionOverflow = overflow
            cameraCorrectionAttempts += 1
            cameraCorrectionAppliedRevision = scheduledCameraRevision
            requestedCameraDistance = distance
            position = .camera(correctedCamera)
            model.traceUIInteraction(
                "map route annotation correction scale=\(String(format: "%.3f", scale)) "
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
        if !preservingSettledCamera { lastSettledCamera = nil }
    }

    private func fitAll(force: Bool = false) {
        guard force || !userMovedMap else { return }
        let alreadyAutomatic = usesNativeAutomaticFit
        resetCameraBoundsCorrection(preservingSettledCamera: alreadyAutomatic)
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
        if model.location.lastFix == nil {
            requestedMapRect = nil
            usesNativeAutomaticFit = true
            position = .automatic
            model.traceUIInteraction("map route native automatic fit applied")
            if alreadyAutomatic, lastSettledCamera != nil {
                cameraCorrectionRequestToken &+= 1
            }
            return
        }
        usesNativeAutomaticFit = false
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: min(170, max((maxLat - minLat) * 1.4, 0.05)),
            longitudeDelta: min(340, max((maxLon - minLon) * 1.4, 0.05))
        )
        let region = MKCoordinateRegion(center: center, span: span)
        if mapViewportSize.width > 1, mapViewportSize.height > 1 {
            let rect = mapRect(for: region, viewport: mapViewportSize)
            requestedMapRect = rect
            position = .region(MKCoordinateRegion(rect))
        } else {
            requestedMapRect = nil
            position = .region(region)
        }
    }

    private func mapRect(for region: MKCoordinateRegion, viewport: CGSize) -> MKMapRect {
        let latitudeLimit = 85.05112878
        let northLatitude = min(latitudeLimit, region.center.latitude + region.span.latitudeDelta / 2)
        let southLatitude = max(-latitudeLimit, region.center.latitude - region.span.latitudeDelta / 2)
        let westLongitude = region.center.longitude - region.span.longitudeDelta / 2
        let eastLongitude = region.center.longitude + region.span.longitudeDelta / 2
        let northwest = MKMapPoint(CLLocationCoordinate2D(latitude: northLatitude, longitude: westLongitude))
        let southeast = MKMapPoint(CLLocationCoordinate2D(latitude: southLatitude, longitude: eastLongitude))
        let base = MKMapRect(
            x: min(northwest.x, southeast.x),
            y: min(northwest.y, southeast.y),
            width: max(1, abs(southeast.x - northwest.x)),
            height: max(1, abs(southeast.y - northwest.y))
        )

        // Keep the pin disc and localized freshness caption inside the actual map
        // canvas. The title is supplied by the selected-person panel below.
        let sideInset: CGFloat = 60
        let topInset: CGFloat = 44
        let bottomInset: CGFloat = 40
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
}
