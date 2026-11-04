import Foundation
import TrustCore
import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class TrustMapCameraBoundsTests: XCTestCase {
    func testUniformFixedPixelAnnotationsScaleFromAnchorSpread() {
        let footprints = [
            TrustMapAnnotationFootprint(point: CGPoint(x: 0, y: 100), size: CGSize(width: 40, height: 40), anchor: .center),
            TrustMapAnnotationFootprint(point: CGPoint(x: 300, y: 100), size: CGSize(width: 40, height: 40), anchor: .center)
        ]

        let correction = TrustMapCameraBounds.correction(
            footprints: footprints,
            cameraCenter: CGPoint(x: 150, y: 100),
            usableViewport: CGRect(x: 0, y: 0, width: 300, height: 200),
            tolerance: 0
        )

        XCTAssertNotNil(correction)
        XCTAssertEqual(correction?.scale ?? 0, CGFloat((300.0 / 260.0) * 1.05), accuracy: 0.001)
        XCTAssertEqual(correction?.translation.x ?? 0, 0, accuracy: 0.001)
        XCTAssertEqual(correction?.translation.y ?? 0, 0, accuracy: 0.001)
        XCTAssertGreaterThan(correction?.overflow ?? 0, 0)
    }

    func testVariedFixedExtentsAndAnchorStylesSetScale() {
        let footprints = [
            TrustMapAnnotationFootprint(point: CGPoint(x: 10, y: 100), size: CGSize(width: 100, height: 70), anchor: .bottom),
            TrustMapAnnotationFootprint(point: CGPoint(x: 290, y: 100), size: CGSize(width: 40, height: 80), anchor: .center)
        ]

        let correction = TrustMapCameraBounds.correction(
            footprints: footprints,
            cameraCenter: CGPoint(x: 150, y: 100),
            usableViewport: CGRect(x: 0, y: 0, width: 300, height: 200),
            tolerance: 0
        )

        XCTAssertNotNil(correction)
        XCTAssertEqual(correction?.scale ?? 0, CGFloat((280.0 / 230.0) * 1.05), accuracy: 0.001)
    }

    func testOnePinRecentersWithoutZoomingIn() {
        let footprints = [
            TrustMapAnnotationFootprint(point: CGPoint(x: 10, y: 10), size: CGSize(width: 40, height: 40), anchor: .center)
        ]

        let correction = TrustMapCameraBounds.correction(
            footprints: footprints,
            cameraCenter: CGPoint(x: 150, y: 100),
            usableViewport: CGRect(x: 0, y: 0, width: 300, height: 200),
            tolerance: 0
        )

        XCTAssertNotNil(correction)
        XCTAssertEqual(correction?.scale ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(correction?.translation.x ?? 0, 140, accuracy: 0.001)
        XCTAssertEqual(correction?.translation.y ?? 0, 90, accuracy: 0.001)
    }

    func testAsymmetricSafeViewportUsesItsActualOriginAndSize() {
        let correction = TrustMapCameraBounds.correction(
            footprints: [
                TrustMapAnnotationFootprint(point: CGPoint(x: 15, y: 100), size: CGSize(width: 40, height: 40), anchor: .center)
            ],
            cameraCenter: CGPoint(x: 150, y: 100),
            usableViewport: CGRect(x: 24, y: 12, width: 240, height: 180),
            tolerance: 0
        )

        XCTAssertNotNil(correction)
        XCTAssertEqual(correction?.scale ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(correction?.translation.x ?? 0, 129, accuracy: 0.001)
        XCTAssertEqual(correction?.translation.y ?? 0, 2, accuracy: 0.001)
    }

    func testAlreadyContainedBoundsRequireNoCorrection() {
        let correction = TrustMapCameraBounds.correction(
            footprints: [
                TrustMapAnnotationFootprint(point: CGPoint(x: 150, y: 100), size: CGSize(width: 40, height: 40), anchor: .center)
            ],
            cameraCenter: CGPoint(x: 150, y: 100),
            usableViewport: CGRect(x: 0, y: 0, width: 300, height: 200)
        )

        XCTAssertNotNil(correction)
        XCTAssertFalse(correction?.isNeeded ?? true)
        XCTAssertEqual(correction?.scale ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(correction?.translation, .zero)
    }

    func testInfeasibleAndInvalidGeometryReturnsNil() {
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 160)
        XCTAssertNil(TrustMapCameraBounds.correction(
            footprints: [],
            cameraCenter: CGPoint(x: 100, y: 80),
            usableViewport: viewport
        ))
        XCTAssertNil(TrustMapCameraBounds.correction(
            footprints: [
                TrustMapAnnotationFootprint(point: CGPoint(x: 100, y: 80), size: CGSize(width: 220, height: 40), anchor: .center)
            ],
            cameraCenter: CGPoint(x: 100, y: 80),
            usableViewport: viewport
        ))
        XCTAssertNil(TrustMapCameraBounds.correction(
            footprints: [
                TrustMapAnnotationFootprint(point: CGPoint(x: 0, y: 80), size: CGSize(width: 200, height: 40), anchor: .center),
                TrustMapAnnotationFootprint(point: CGPoint(x: 200, y: 80), size: CGSize(width: 200, height: 40), anchor: .center)
            ],
            cameraCenter: CGPoint(x: 100, y: 80),
            usableViewport: viewport,
            tolerance: 0
        ))
        XCTAssertNil(TrustMapCameraBounds.correction(
            footprints: [
                TrustMapAnnotationFootprint(point: CGPoint(x: CGFloat.nan, y: 80), size: CGSize(width: 40, height: 40), anchor: .center)
            ],
            cameraCenter: CGPoint(x: 100, y: 80),
            usableViewport: viewport
        ))
        XCTAssertNil(TrustMapCameraBounds.correction(
            footprints: [
                TrustMapAnnotationFootprint(point: CGPoint(x: 100, y: 80), size: CGSize(width: CGFloat.infinity, height: 40), anchor: .center)
            ],
            cameraCenter: CGPoint(x: 100, y: 80),
            usableViewport: viewport
        ))
        XCTAssertNil(TrustMapCameraBounds.correction(
            footprints: [
                TrustMapAnnotationFootprint(point: CGPoint(x: 100, y: 80), size: CGSize(width: 40, height: 40), anchor: .center)
            ],
            cameraCenter: CGPoint(x: 100, y: 80),
            usableViewport: CGRect(x: CGFloat.infinity, y: 0, width: 200, height: 160)
        ))
    }

    func testCaptionStaysCenteredBelowWhenItFits() {
        let candidate = TrustMapCaptionCandidate(
            point: CGPoint(x: 100, y: 80),
            size: CGSize(width: 60, height: 16),
            anchor: .bottom
        )
        let placements = TrustMapCaptionLayout.placements(
            candidates: [candidate],
            discBounds: [TrustMapCaptionLayout.discBounds(
                point: candidate.point,
                anchor: .bottom,
                captionSize: candidate.size
            )],
            viewport: CGRect(x: 0, y: 0, width: 200, height: 160)
        )

        XCTAssertEqual(placements[0], .centeredBelow)
        XCTAssertEqual(
            TrustMapCaptionLayout.captionBounds(for: candidate, placement: placements[0]!),
            CGRect(x: 70, y: 64, width: 60, height: 16)
        )
    }

    func testCaptionMovesInwardToKeepFullLocalizedWidthInsideViewport() {
        let candidate = TrustMapCaptionCandidate(
            point: CGPoint(x: 12, y: 80),
            size: CGSize(width: 70, height: 16),
            anchor: .bottom
        )
        let placements = TrustMapCaptionLayout.placements(
            candidates: [candidate],
            discBounds: [TrustMapCaptionLayout.discBounds(
                point: candidate.point,
                anchor: .bottom,
                captionSize: candidate.size
            )],
            viewport: CGRect(x: 0, y: 0, width: 200, height: 160)
        )

        XCTAssertEqual(placements[0]?.side, .below)
        XCTAssertEqual(placements[0]?.horizontalOffset ?? 0, 31, accuracy: 0.001)
        let bounds = TrustMapCaptionLayout.captionBounds(for: candidate, placement: placements[0]!)
        XCTAssertEqual(bounds.minX, 8, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 78, accuracy: 0.001)
    }

    func testDiscCollisionMovesCaptionAboveWithoutMovingDisc() {
        let candidate = TrustMapCaptionCandidate(
            point: CGPoint(x: 50, y: 100),
            size: CGSize(width: 60, height: 16),
            anchor: .bottom
        )
        let ownDisc = TrustMapCaptionLayout.discBounds(
            point: candidate.point,
            anchor: .bottom,
            captionSize: candidate.size
        )
        let neighborDisc = CGRect(x: 28, y: 82, width: 44, height: 44)
        let placements = TrustMapCaptionLayout.placements(
            candidates: [candidate, nil],
            discBounds: [ownDisc, neighborDisc],
            viewport: CGRect(x: 0, y: 0, width: 200, height: 160)
        )

        XCTAssertEqual(placements[0]?.side, .above)
        XCTAssertEqual(placements[0]?.horizontalOffset ?? 0, 0, accuracy: 0.001)
        XCTAssertEqual(ownDisc, CGRect(x: 28, y: 40, width: 44, height: 44))
        let footprint = TrustMapCaptionLayout.footprint(
            point: candidate.point,
            anchor: .bottom,
            captionSize: candidate.size,
            placement: placements[0]!
        )
        XCTAssertEqual(footprint.point, candidate.point)
        XCTAssertEqual(
            TrustMapCaptionLayout.captionBounds(for: candidate, placement: placements[0]!),
            CGRect(x: 20, y: 24, width: 60, height: 16)
        )
    }

    func testStableInputOrderKeepsNearbyCapsulesFromOverlapping() {
        let first = TrustMapCaptionCandidate(
            point: CGPoint(x: 40, y: 80),
            size: CGSize(width: 100, height: 16),
            anchor: .bottom
        )
        let second = TrustMapCaptionCandidate(
            point: CGPoint(x: 160, y: 80),
            size: CGSize(width: 100, height: 16),
            anchor: .bottom
        )
        let placements = TrustMapCaptionLayout.placements(
            candidates: [first, second],
            discBounds: [
                TrustMapCaptionLayout.discBounds(point: first.point, anchor: .bottom, captionSize: first.size),
                TrustMapCaptionLayout.discBounds(point: second.point, anchor: .bottom, captionSize: second.size)
            ],
            viewport: CGRect(x: 0, y: 0, width: 300, height: 180)
        )

        XCTAssertEqual(placements[0]?.side, .below)
        XCTAssertEqual(placements[1]?.side, .above)
        let firstBounds = TrustMapCaptionLayout.captionBounds(for: first, placement: placements[0]!)
        let secondBounds = TrustMapCaptionLayout.captionBounds(for: second, placement: placements[1]!)
        XCTAssertFalse(firstBounds.insetBy(dx: -4, dy: -4).intersects(secondBounds))
    }

    func testAboveCaptionFootprintUsesAsymmetricBoundsAroundUnmovedAnchor() {
        let point = CGPoint(x: 100, y: 100)
        let size = CGSize(width: 70, height: 16)
        let footprint = TrustMapCaptionLayout.footprint(
            point: point,
            anchor: .bottom,
            captionSize: size,
            placement: TrustMapCaptionPlacement(side: .above, horizontalOffset: 5)
        )

        XCTAssertEqual(footprint.point, point)
        XCTAssertEqual(footprint.relativeBounds.minX, -30, accuracy: 0.001)
        XCTAssertEqual(footprint.relativeBounds.maxX, 40, accuracy: 0.001)
        XCTAssertEqual(footprint.top, 76, accuracy: 0.001)
        XCTAssertEqual(footprint.bottom, -18, accuracy: 0.001)
        XCTAssertEqual(footprint.frame(at: point).minY, 24, accuracy: 0.001)
    }

    func testPinGeometryKeepsBottomAndCenterGeographicAnchorsOnDiscAcrossCaptionMoves() {
        let captionSize = CGSize(width: 72, height: 16)
        let minimumFrame = CGSize(width: 44, height: 44)
        for anchor in [TrustMapAnnotationAnchor.bottom, .center] {
            let below = TrustMapCaptionLayout.pinGeometry(
                anchor: anchor,
                captionSize: captionSize,
                placement: .centeredBelow,
                minimumFrame: minimumFrame
            )
            let above = TrustMapCaptionLayout.pinGeometry(
                anchor: anchor,
                captionSize: captionSize,
                placement: TrustMapCaptionPlacement(side: .above, horizontalOffset: 12),
                minimumFrame: minimumFrame
            )

            let belowDisc = CGPoint(x: below.discFrameInContent.midX, y: below.discFrameInContent.midY)
            let aboveDisc = CGPoint(x: above.discFrameInContent.midX, y: above.discFrameInContent.midY)
            let belowGeographicPoint = CGPoint(
                x: below.annotationAnchor.x * below.contentSize.width,
                y: below.annotationAnchor.y * below.contentSize.height
            )
            let aboveGeographicPoint = CGPoint(
                x: above.annotationAnchor.x * above.contentSize.width,
                y: above.annotationAnchor.y * above.contentSize.height
            )

            XCTAssertEqual(belowDisc.x - belowGeographicPoint.x, 0, accuracy: 0.001)
            XCTAssertEqual(aboveDisc.x - aboveGeographicPoint.x, 0, accuracy: 0.001)
            XCTAssertEqual(belowDisc.y - belowGeographicPoint.y, aboveDisc.y - aboveGeographicPoint.y, accuracy: 0.001)
            XCTAssertNotEqual(above.annotationAnchor.x, below.annotationAnchor.x)
        }
    }

    func testBottomPinAnchorUsesOuterFrameExpansionForNoCaption() {
        let circle = TrustMapCaptionLayout.pinGeometry(
            anchor: .bottom,
            captionSize: nil,
            minimumFrame: CGSize(width: 44, height: 44)
        )
        let centerMap = TrustMapCaptionLayout.pinGeometry(
            anchor: .center,
            captionSize: nil,
            minimumFrame: CGSize(width: 44, height: 44)
        )

        XCTAssertEqual(circle.annotationAnchor.y, 1, accuracy: 0.001)
        XCTAssertEqual(circle.discFrameInContent.midY - circle.annotationAnchor.y * circle.contentSize.height, -22, accuracy: 0.001)
        XCTAssertEqual(centerMap.annotationAnchor.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(centerMap.discFrameInContent.midY - centerMap.annotationAnchor.y * centerMap.contentSize.height, 0, accuracy: 0.001)
    }

    func testPinGeometryHitBoundsMatchCaptionAndInwardDiscLayout() {
        let layout = TrustMapCaptionLayout.pinGeometry(
            anchor: .bottom,
            captionSize: CGSize(width: 72, height: 16),
            placement: TrustMapCaptionPlacement(side: .above, horizontalOffset: 12),
            minimumFrame: CGSize(width: 44, height: 44)
        )
        let caption = try! XCTUnwrap(layout.captionFrameInContent)
        XCTAssertEqual(caption.width, 72, accuracy: 0.001)
        XCTAssertEqual(caption.midX - layout.discFrameInContent.midX, 12, accuracy: 0.001)
        XCTAssertTrue(layout.hitBoundsToGeographicAnchor.contains(CGPoint(
            x: layout.discBoundsToGeographicAnchor.midX,
            y: layout.discBoundsToGeographicAnchor.midY
        )))
        XCTAssertTrue(layout.hitBoundsToGeographicAnchor.intersects(layout.relativeBoundsToGeographicAnchor))
        XCTAssertGreaterThan(layout.annotationAnchor.y, 1, "An above caption with a bottom geographic anchor places the anchor below the rendered box.")
    }

    func testPinGeometryIncludesVisibleStaleBadgeInRenderedBounds() {
        let regular = TrustMapCaptionLayout.pinGeometry(anchor: .center, captionSize: nil)
        let stale = TrustMapCaptionLayout.pinGeometry(anchor: .center, captionSize: nil, stale: true)

        XCTAssertGreaterThan(stale.contentBounds.maxX, regular.contentBounds.maxX)
        XCTAssertLessThan(stale.contentBounds.minY, regular.contentBounds.minY)
        XCTAssertEqual(stale.relativeBoundsToGeographicAnchor, stale.contentBounds)
    }

    func testImpossibleCaptionWidthAndVerticalSpaceRemainUnresolved() {
        let tooWide = TrustMapCaptionCandidate(
            point: CGPoint(x: 100, y: 80),
            size: CGSize(width: 185, height: 16),
            anchor: .bottom
        )
        let tooTall = TrustMapCaptionCandidate(
            point: CGPoint(x: 100, y: 8),
            size: CGSize(width: 60, height: 16),
            anchor: .bottom
        )
        let discBounds = [
            TrustMapCaptionLayout.discBounds(point: tooWide.point, anchor: .bottom, captionSize: tooWide.size),
            TrustMapCaptionLayout.discBounds(point: tooTall.point, anchor: .bottom, captionSize: tooTall.size)
        ]
        let placements = TrustMapCaptionLayout.placements(
            candidates: [tooWide, tooTall],
            discBounds: discBounds,
            viewport: CGRect(x: 0, y: 0, width: 200, height: 100)
        )

        XCTAssertNil(placements[0])
        XCTAssertNil(placements[1])
    }

    func testOffscreenDiscDoesNotPullItsCaptionToViewportEdge() {
        let candidate = TrustMapCaptionCandidate(
            point: CGPoint(x: -1_000, y: 80),
            size: CGSize(width: 70, height: 16),
            anchor: .bottom
        )
        let placements = TrustMapCaptionLayout.placements(
            candidates: [candidate],
            discBounds: [CGRect(x: -1_022, y: 22, width: 44, height: 44)],
            viewport: CGRect(x: 0, y: 0, width: 200, height: 160)
        )

        XCTAssertNil(placements[0])
    }

    func testAsymmetricFootprintsWhoseUnionCannotFitReturnNil() {
        let footprints = [
            TrustMapAnnotationFootprint(
                point: CGPoint(x: 0, y: 50),
                relativeBounds: CGRect(x: -10, y: -10, width: 180, height: 20)
            ),
            TrustMapAnnotationFootprint(
                point: CGPoint(x: 100, y: 50),
                relativeBounds: CGRect(x: -170, y: -10, width: 180, height: 20)
            )
        ]

        XCTAssertNil(TrustMapCameraBounds.correction(
            footprints: footprints,
            cameraCenter: CGPoint(x: 50, y: 50),
            usableViewport: CGRect(x: 0, y: 0, width: 200, height: 100),
            tolerance: 0
        ))
    }
}
