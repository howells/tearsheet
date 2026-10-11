import Foundation
import Testing
@testable import TearsheetCore

struct CaptureFilenameTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test func matchesMacOSNaming() {
        let date = Date(timeIntervalSince1970: 1_791_729_125) // 2026-10-11 14:32:05 UTC
        #expect(CaptureFilename.name(for: date, timeZone: utc) == "Screenshot 2026-10-11 at 14.32.05.png")
    }

    @Test func usesTwentyFourHourClock() {
        let date = Date(timeIntervalSince1970: 1_791_759_599) // 2026-10-11 22:59:59 UTC
        #expect(CaptureFilename.name(for: date, timeZone: utc).contains("22.59.59"))
    }

    @Test func returnsNameWhenFree() {
        let folder = URL(filePath: "/tmp/x")
        let url = CaptureFilename.uniqueURL(in: folder, name: "Shot.png") { _ in false }
        #expect(url.lastPathComponent == "Shot.png")
    }

    @Test func numbersCollisions() {
        let folder = URL(filePath: "/tmp/x")
        let taken: Set = ["Shot.png", "Shot (2).png"]
        let url = CaptureFilename.uniqueURL(in: folder, name: "Shot.png") { taken.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "Shot (3).png")
    }
}
