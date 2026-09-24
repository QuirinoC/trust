import Foundation

public enum LocationTrail {
    /// Mission District–ish walk used for the review simulator feed.
    public static let home = LocationPoint(
        timestamp: Date(timeIntervalSince1970: 0),
        latitude: 37.7599,
        longitude: -122.4148
    )

    /// Distinct US demo pins for lean MapKit circle (DEBUG).
    public enum DemoCity: String, CaseIterable, Sendable {
        case missionSF
        case capitolHillSeattle
        case brooklyn
        case austin
        case chicago
        case miami
        case denver
        case portland
        case veniceLA
        case sohoNYC

        public var label: String {
            switch self {
            case .missionSF: return "Mission"
            case .capitolHillSeattle: return "Capitol Hill"
            case .brooklyn: return "Brooklyn"
            case .austin: return "Austin"
            case .chicago: return "Chicago"
            case .miami: return "Miami"
            case .denver: return "Denver"
            case .portland: return "Portland"
            case .veniceLA: return "Venice"
            case .sohoNYC: return "SoHo"
            }
        }

        public var latitude: Double {
            switch self {
            case .missionSF: return 37.7599
            case .capitolHillSeattle: return 47.6253
            case .brooklyn: return 40.6782
            case .austin: return 30.2672
            case .chicago: return 41.8781
            case .miami: return 25.7617
            case .denver: return 39.7392
            case .portland: return 45.5152
            case .veniceLA: return 33.9850
            case .sohoNYC: return 40.7233
            }
        }

        public var longitude: Double {
            switch self {
            case .missionSF: return -122.4148
            case .capitolHillSeattle: return -122.3222
            case .brooklyn: return -73.9442
            case .austin: return -97.7431
            case .chicago: return -87.6298
            case .miami: return -80.1918
            case .denver: return -104.9903
            case .portland: return -122.6784
            case .veniceLA: return -118.4695
            case .sohoNYC: return -74.0030
            }
        }

        public func point(at time: Date = Date(timeIntervalSince1970: 0)) -> LocationPoint {
            LocationPoint(timestamp: time, latitude: latitude, longitude: longitude)
        }
    }

    public static func seed(
        around origin: LocationPoint,
        now: Date,
        hours: Double,
        intervalMinutes: Double = 5,
        drift: Double = 0
    ) -> [LocationPoint] {
        let totalMinutes = hours * 60
        let steps = Int(totalMinutes / intervalMinutes)
        return (0...steps).map { index in
            let minutesAgo = totalMinutes - Double(index) * intervalMinutes
            let progress = Double(index) / Double(max(steps, 1))
            let lat = origin.latitude
                + 0.004 * sin(progress * .pi * 2)
                + 0.0015 * progress
                + drift
            let lon = origin.longitude
                + 0.005 * (cos(progress * .pi * 2) - 1)
                - 0.0008 * progress
                + drift * 0.6
            return LocationPoint(
                timestamp: now.addingTimeInterval(-minutesAgo * 60),
                latitude: lat,
                longitude: lon
            )
        }
    }

    public static func step(_ point: LocationPoint, at time: Date, phase: Double) -> LocationPoint {
        LocationPoint(
            timestamp: time,
            latitude: point.latitude + 0.00012 * sin(phase),
            longitude: point.longitude + 0.00012 * cos(phase * 0.7)
        )
    }

    public static func isNearHome(_ point: LocationPoint, home: LocationPoint = home) -> Bool {
        let dlat = point.latitude - home.latitude
        let dlon = point.longitude - home.longitude
        let meters = sqrt(dlat * dlat + dlon * dlon) * 111_000
        return meters < 120
    }
}
