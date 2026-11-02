import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum TrustMapAnnotationAnchor: Equatable {
    case bottom
    case center
}

public struct TrustMapAnnotationFootprint: Equatable {
    public let point: CGPoint
    public let size: CGSize
    public let anchor: TrustMapAnnotationAnchor
    /// Bounds relative to the geographic annotation point. Allows overlays such
    /// as an above-disc caption to extend asymmetrically without moving the pin.
    public let relativeBounds: CGRect

    public init(point: CGPoint, size: CGSize, anchor: TrustMapAnnotationAnchor) {
        self.point = point
        self.size = size
        self.anchor = anchor
        switch anchor {
        case .bottom:
            relativeBounds = CGRect(x: -size.width / 2, y: -size.height, width: size.width, height: size.height)
        case .center:
            relativeBounds = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        }
    }

    public init(point: CGPoint, relativeBounds: CGRect) {
        self.point = point
        self.size = relativeBounds.size
        self.anchor = .center
        self.relativeBounds = relativeBounds
    }

    public var left: CGFloat { -relativeBounds.minX }
    public var right: CGFloat { relativeBounds.maxX }
    public var top: CGFloat { -relativeBounds.minY }
    public var bottom: CGFloat { relativeBounds.maxY }

    public func frame(at point: CGPoint) -> CGRect {
        relativeBounds.offsetBy(dx: point.x, dy: point.y)
    }
}

public enum TrustMapCaptionSide: Equatable {
    case below
    case above
}

public struct TrustMapCaptionPlacement: Equatable {
    public let side: TrustMapCaptionSide
    public let horizontalOffset: CGFloat

    public init(side: TrustMapCaptionSide = .below, horizontalOffset: CGFloat = 0) {
        self.side = side
        self.horizontalOffset = horizontalOffset
    }

    public static let centeredBelow = TrustMapCaptionPlacement()
}

/// Geometry shared by a rendered pin, its MapKit anchor, camera bounds, and hit tests.
/// All relative rectangles use the visible disc center as their origin.
public struct TrustMapPinGeometryLayout: Equatable {
    public let contentBounds: CGRect
    public let discFrameInContent: CGRect
    public let captionFrameInContent: CGRect?
    public let relativeBoundsToGeographicAnchor: CGRect
    public let discBoundsToGeographicAnchor: CGRect
    public let hitBoundsToGeographicAnchor: CGRect
    public let annotationAnchor: CGPoint
    public let contentSize: CGSize
}

public struct TrustMapCaptionCandidate: Equatable {
    public let point: CGPoint
    public let size: CGSize
    public let anchor: TrustMapAnnotationAnchor

    public init(point: CGPoint, size: CGSize, anchor: TrustMapAnnotationAnchor) {
        self.point = point
        self.size = size
        self.anchor = anchor
    }
}

public enum TrustMapCaptionLayout {
    /// Positions localized freshness capsules below by default. If the full
    /// capsule would leave the viewport or collide with a different pin/caption,
    /// it tries above the same disc. Input order is the stable tie-breaker.
    public static func placements(
        candidates: [TrustMapCaptionCandidate?],
        discBounds: [CGRect],
        viewport: CGRect,
        edgeInset: CGFloat = 8,
        collisionClearance: CGFloat = 4,
        gap: CGFloat = 2
    ) -> [TrustMapCaptionPlacement?] {
        guard candidates.count == discBounds.count,
              isFinite(viewport), viewport.width > 1, viewport.height > 1,
              edgeInset.isFinite, edgeInset >= 0,
              collisionClearance.isFinite, collisionClearance >= 0,
              gap.isFinite, gap >= 0 else {
            return Array(repeating: nil, count: candidates.count)
        }

        var output = Array<TrustMapCaptionPlacement?>(repeating: nil, count: candidates.count)
        var placedLabels: [CGRect] = []
        for index in candidates.indices {
            guard let candidate = candidates[index],
                  isFinite(candidate.point), isFinite(candidate.size),
                  candidate.size.width > 0, candidate.size.height > 0,
                  isFinite(discBounds[index]), discBounds[index].width > 0, discBounds[index].height > 0,
                  discBounds[index].intersects(viewport) else { continue }
            let minimumCenter = viewport.minX + edgeInset + candidate.size.width / 2
            let maximumCenter = viewport.maxX - edgeInset - candidate.size.width / 2
            guard minimumCenter <= maximumCenter else { continue }
            let centerX = min(max(candidate.point.x, minimumCenter), maximumCenter)
            let horizontalOffset = centerX - candidate.point.x

            for side in [TrustMapCaptionSide.below, .above] {
                let placement = TrustMapCaptionPlacement(side: side, horizontalOffset: horizontalOffset)
                let label = captionBounds(for: candidate, placement: placement, gap: gap)
                guard label.minY >= viewport.minY, label.maxY <= viewport.maxY else { continue }
                let protectedLabel = label.insetBy(dx: -collisionClearance, dy: -collisionClearance)
                let hitsDisc = discBounds.enumerated().contains { otherIndex, disc in
                    otherIndex != index && protectedLabel.intersects(disc)
                }
                let hitsLabel = placedLabels.contains { protectedLabel.intersects($0) }
                guard !hitsDisc, !hitsLabel else { continue }
                output[index] = placement
                placedLabels.append(label)
                break
            }
        }
        return output
    }

    public static func captionBounds(
        for candidate: TrustMapCaptionCandidate,
        placement: TrustMapCaptionPlacement,
        gap: CGFloat = 2
    ) -> CGRect {
        let geometry = pinGeometry(
            anchor: candidate.anchor,
            captionSize: candidate.size,
            placement: placement,
            minimumFrame: CGSize(width: 44, height: 44),
            gap: gap
        )
        guard let caption = geometry.captionFrameInContent else { return .zero }
        return caption.offsetBy(
            dx: candidate.point.x - (geometry.annotationAnchor.x * geometry.contentSize.width),
            dy: candidate.point.y - (geometry.annotationAnchor.y * geometry.contentSize.height)
        )
    }

    /// Builds the exact rendered pin box and the anchor needed to keep its disc at
    /// the same geographic point as the original below-caption stack.
    public static func pinGeometry(
        anchor: TrustMapAnnotationAnchor,
        captionSize: CGSize?,
        placement: TrustMapCaptionPlacement = .centeredBelow,
        stale: Bool = false,
        minimumFrame: CGSize = .zero,
        gap: CGFloat = 2
    ) -> TrustMapPinGeometryLayout {
        let validCaption: CGSize? = captionSize.flatMap { size in
            isFinite(size) && size.width > 0 && size.height > 0 ? size : nil
        }
        let validMinimum = CGSize(
            width: minimumFrame.width.isFinite ? max(0, minimumFrame.width) : 0,
            height: minimumFrame.height.isFinite ? max(0, minimumFrame.height) : 0
        )
        let safeGap = gap.isFinite ? max(0, gap) : 2
        let safeHorizontalOffset = placement.horizontalOffset.isFinite ? placement.horizontalOffset : 0
        let discView = CGRect(x: -20, y: -20, width: 40, height: 40)
        let disc = stale
            ? CGRect(x: -20, y: -22, width: 43, height: 42)
            : discView
        let discHitBounds = CGRect(x: -22, y: -22, width: 44, height: 44)
        let caption: CGRect? = validCaption.map { size in
            let x = safeHorizontalOffset - size.width / 2
            let y = placement.side == .above ? -20 - safeGap - size.height : 20 + safeGap
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }
        var bounds = disc
        if let caption { bounds = bounds.union(caption) }
        let expandedWidth = max(bounds.width, validMinimum.width)
        let expandedHeight = max(bounds.height, validMinimum.height)
        bounds = CGRect(
            x: bounds.minX - (expandedWidth - bounds.width) / 2,
            y: bounds.minY - (expandedHeight - bounds.height) / 2,
            width: expandedWidth,
            height: expandedHeight
        )

        let legacyContentHeight = validCaption.map { 42 + $0.height } ?? 40
        let anchorOffsetFromDiscCenter: CGFloat
        switch anchor {
        case .bottom:
            let outerHeight = max(validMinimum.height, legacyContentHeight)
            // The original Circle stack was centered inside its min-height frame.
            anchorOffsetFromDiscCenter = outerHeight - (outerHeight - legacyContentHeight) / 2 - 20
        case .center:
            anchorOffsetFromDiscCenter = legacyContentHeight / 2 - 20
        }

        let geographicAnchorInContent = CGPoint(x: -bounds.minX, y: anchorOffsetFromDiscCenter - bounds.minY)
        let relativeBounds = bounds.offsetBy(dx: 0, dy: -anchorOffsetFromDiscCenter)
        let discInContent = discView.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        let captionInContent = caption?.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        let hitBounds = bounds.union(discHitBounds)
        let unitAnchor = CGPoint(
            x: bounds.width > 0 ? geographicAnchorInContent.x / bounds.width : 0.5,
            y: bounds.height > 0 ? geographicAnchorInContent.y / bounds.height : 0.5
        )
        return TrustMapPinGeometryLayout(
            contentBounds: bounds,
            discFrameInContent: discInContent,
            captionFrameInContent: captionInContent,
            relativeBoundsToGeographicAnchor: relativeBounds,
            discBoundsToGeographicAnchor: disc.union(discHitBounds).offsetBy(dx: 0, dy: -anchorOffsetFromDiscCenter),
            hitBoundsToGeographicAnchor: hitBounds.offsetBy(dx: 0, dy: -anchorOffsetFromDiscCenter),
            annotationAnchor: unitAnchor,
            contentSize: bounds.size
        )
    }

    public static func discBounds(
        point: CGPoint,
        anchor: TrustMapAnnotationAnchor,
        captionSize: CGSize?,
        stale: Bool = false
    ) -> CGRect {
        let layout = pinGeometry(
            anchor: anchor,
            captionSize: captionSize,
            stale: stale,
            minimumFrame: CGSize(width: 44, height: 44)
        )
        return layout.discBoundsToGeographicAnchor.offsetBy(dx: point.x, dy: point.y)
    }

    public static func footprint(
        point: CGPoint,
        anchor: TrustMapAnnotationAnchor,
        captionSize: CGSize?,
        placement: TrustMapCaptionPlacement,
        stale: Bool = false,
        gap: CGFloat = 2
    ) -> TrustMapAnnotationFootprint {
        let visibleBounds = pinGeometry(
            anchor: anchor,
            captionSize: captionSize,
            placement: placement,
            stale: stale,
            minimumFrame: CGSize(width: 44, height: 44),
            gap: gap
        ).relativeBoundsToGeographicAnchor.offsetBy(dx: point.x, dy: point.y)
        return TrustMapAnnotationFootprint(
            point: point,
            relativeBounds: visibleBounds.offsetBy(dx: -point.x, dy: -point.y)
        )
    }

    private static func isFinite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    private static func isFinite(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
    }
}

public struct TrustMapCameraBoundsCorrection: Equatable {
    public let scale: CGFloat
    public let translation: CGPoint
    public let overflow: CGFloat

    public init(scale: CGFloat, translation: CGPoint, overflow: CGFloat) {
        self.scale = scale
        self.translation = translation
        self.overflow = overflow
    }

    public var isNeeded: Bool { overflow > 0.5 }
}

public enum TrustMapCameraBounds {
    /// Finds a camera correction for fixed-pixel annotations. Map distance changes
    /// pin spacing, while each annotation's measured frame stays the same size.
    public static func correction(
        footprints: [TrustMapAnnotationFootprint],
        cameraCenter: CGPoint,
        usableViewport: CGRect,
        tolerance: CGFloat = 8
    ) -> TrustMapCameraBoundsCorrection? {
        guard !footprints.isEmpty,
              cameraCenter.x.isFinite, cameraCenter.y.isFinite,
              isFinite(usableViewport), usableViewport.width > 1, usableViewport.height > 1,
              tolerance.isFinite, tolerance >= 0 else { return nil }

        let viewport = usableViewport.insetBy(dx: tolerance, dy: tolerance)
        guard viewport.width > 1, viewport.height > 1 else { return nil }
        for footprint in footprints {
            guard footprint.point.x.isFinite, footprint.point.y.isFinite,
                  footprint.size.width.isFinite, footprint.size.height.isFinite,
                  footprint.size.width > 0, footprint.size.height > 0,
                  footprint.left + footprint.right <= viewport.width,
                  footprint.top + footprint.bottom <= viewport.height else { return nil }
        }

        let originalFrames = footprints.map { $0.frame(at: $0.point) }
        let originalUnion = originalFrames.reduce(CGRect.null) { $0.union($1) }
        guard isFinite(originalUnion) else { return nil }
        let overflow = max(
            max(viewport.minX - originalUnion.minX, originalUnion.maxX - viewport.maxX),
            max(viewport.minY - originalUnion.minY, originalUnion.maxY - viewport.maxY)
        )

        guard overflow > 0.5 else {
            return TrustMapCameraBoundsCorrection(scale: 1, translation: .zero, overflow: 0)
        }

        var scale: CGFloat = 1
        for first in footprints {
            for second in footprints {
                let deltaX = second.point.x - first.point.x
                if deltaX > 0 {
                    let denominator = viewport.width - first.left - second.right
                    guard denominator > 0 else { return nil }
                    scale = max(scale, deltaX / denominator)
                }

                let deltaY = second.point.y - first.point.y
                if deltaY > 0 {
                    let denominator = viewport.height - first.top - second.bottom
                    guard denominator > 0 else { return nil }
                    scale = max(scale, deltaY / denominator)
                }
            }
        }
        guard scale.isFinite, scale >= 1 else { return nil }
        if scale > 1.0001 { scale *= 1.05 }

        let scaledFrames = footprints.map { footprint -> CGRect in
            let point = CGPoint(
                x: cameraCenter.x + (footprint.point.x - cameraCenter.x) / scale,
                y: cameraCenter.y + (footprint.point.y - cameraCenter.y) / scale
            )
            return footprint.frame(at: point)
        }
        let scaledUnion = scaledFrames.reduce(CGRect.null) { $0.union($1) }
        guard isFinite(scaledUnion),
              scaledUnion.width <= viewport.width + 0.5,
              scaledUnion.height <= viewport.height + 0.5 else { return nil }
        let translation = CGPoint(x: viewport.midX - scaledUnion.midX, y: viewport.midY - scaledUnion.midY)
        guard translation.x.isFinite, translation.y.isFinite else { return nil }
        return TrustMapCameraBoundsCorrection(scale: scale, translation: translation, overflow: overflow)
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
    }
}
