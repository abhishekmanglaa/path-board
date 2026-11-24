import XCTest
import CoreLocation

final class CommuteUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testFixedStationAndSettingsPersist() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        XCTAssertTrue(app.buttons["stationPicker"].waitForExistence(timeout: 15))
        app.buttons["stationPicker"].tap()
        let wtc = app.buttons["station-WTC"].firstMatch
        XCTAssertTrue(wtc.waitForExistence(timeout: 5))
        wtc.tap()
        XCTAssertTrue(app.buttons["stationPicker"].label.contains("World Trade Center") || app.staticTexts["World Trade Center"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["settings"].exists)
        app.buttons["settings"].tap()
        XCTAssertTrue(app.steppers["stationBuffer"].waitForExistence(timeout: 5))
        let increment = app.buttons["stationBuffer-Increment"]
        if increment.isEnabled { increment.tap() }
        else { app.buttons["stationBuffer-Decrement"].tap() }
        let buffer = app.steppers["stationBuffer"].label
        app.buttons["Done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["stationPicker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["stationPicker"].label.contains("World Trade Center"))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.steppers["stationBuffer"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.steppers["stationBuffer"].label, buffer)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Settings on iPhone"; shot.lifetime = .keepAlways; add(shot)
    }

    func testStationSearchPinAndRefresh() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["stationPicker"].waitForExistence(timeout: 10))
        app.buttons["stationPicker"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Christopher")
        let station = app.buttons["station-CHR"].firstMatch
        XCTAssertTrue(station.waitForExistence(timeout: 5))
        station.tap()
        XCTAssertTrue(app.buttons["refreshDepartures"].waitForExistence(timeout: 10))
        app.buttons["refreshDepartures"].tap()
        XCTAssertTrue(app.buttons["stationPicker"].label.contains("Christopher Street"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Fixed station without location"; shot.lifetime = .keepAlways; add(shot)
    }

    func testTrackAndEndLiveActivity() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 40.7330, longitude: -74.0071))
        defer { XCUIDevice.shared.location = nil }
        app.launch()
        XCTAssertTrue(app.buttons["stationPicker"].waitForExistence(timeout: 10))
        app.buttons["stationPicker"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Christopher")
        app.buttons["station-CHR"].firstMatch.tap()
        let addLocation = app.buttons["Add walking time with location"]
        if addLocation.waitForExistence(timeout: 5) {
            if !addLocation.isHittable { app.swipeUp() }
            addLocation.tap()
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow While Using App"]
            XCTAssertTrue(allow.waitForExistence(timeout: 10))
            allow.tap()
            app.swipeDown()
        }
        let canTrack = app.buttons["startActivity"].waitForExistence(timeout: 45)
        if !canTrack { print("TRACKING SCREEN", app.debugDescription) }
        XCTAssertTrue(canTrack, "A fresh nearby fix must enable train tracking")
        app.buttons["startActivity"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["endActivity"].waitForExistence(timeout: 10), "ActivityKit request must succeed")
        app.buttons["endActivity"].tap()
        let ended = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["endActivity"])
        XCTAssertEqual(XCTWaiter.wait(for: [ended], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["stationPicker"].exists)
    }
}
