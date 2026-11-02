import Foundation
import XCTest
@testable import TrustCore

final class TrustDateLocalizationTests: XCTestCase {
    func testRelativeLocationAgeUsesSelectedLanguageAndExplicitReferenceTime() {
        let previous = UserDefaults.standard.string(forKey: TrustAppLanguage.storageKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: TrustAppLanguage.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: TrustAppLanguage.storageKey)
            }
        }

        let locales: [(language: TrustAppLanguage, marker: String)] = [
            (.english, "ago"),
            (.german, "vor"),
            (.french, "il y a"),
            (.japanese, "前"),
            (.brazilianPortuguese, "há"),
            (.simplifiedChinese, "前")
        ]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timestamp = now.addingTimeInterval(-2 * 60 * 60)

        for (language, marker) in locales {
            UserDefaults.standard.set(language.rawValue, forKey: TrustAppLanguage.storageKey)
            let first = TrustCopy.locationAgeCaption(timestamp: timestamp, now: now)
            let later = TrustCopy.locationAgeCaption(timestamp: timestamp, now: now.addingTimeInterval(60 * 60))

            XCTAssertTrue(first.localizedCaseInsensitiveContains(marker), "Unexpected \(language.rawValue) age: \(first)")
            XCTAssertNotEqual(first, later, "The explicit reference time must affect \(language.rawValue) age.")
        }
    }

    func testAbsoluteDateUsesSelectedLanguage() {
        let previous = UserDefaults.standard.string(forKey: TrustAppLanguage.storageKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: TrustAppLanguage.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: TrustAppLanguage.storageKey)
            }
        }

        let locales: [(language: TrustAppLanguage, month: String)] = [
            (.english, "January"),
            (.german, "Januar"),
            (.french, "janvier"),
            (.japanese, "月"),
            (.brazilianPortuguese, "janeiro"),
            (.simplifiedChinese, "月")
        ]
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2025
        components.month = 1
        components.day = 2
        components.hour = 12
        let date = try! XCTUnwrap(components.date)

        for (language, month) in locales {
            UserDefaults.standard.set(language.rawValue, forKey: TrustAppLanguage.storageKey)
            let formatted = TrustCopy.formattedDateTime(date, dateStyle: .complete, timeStyle: .omitted)
            XCTAssertTrue(formatted.localizedCaseInsensitiveContains(month), "Unexpected \(language.rawValue) date: \(formatted)")
        }
    }
}
