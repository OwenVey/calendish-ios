import XCTest
import UIKit

final class HouseholdUITests: XCTestCase {
    private func launch(_ argument: String = "--ui-fixture") -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish-household-workflow")
        app.launchArguments = [argument]
        app.launch()
        return app
    }
    func testOnboardingOnlyAsksForName() {
        let app = launch("--ui-setup")
        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue"].exists)
        XCTAssertFalse(app.buttons["Create Household"].exists)
        XCTAssertFalse(app.textFields["Household name"].exists)
        XCTAssertFalse(app.textFields["Invite code"].exists)
    }
    func testOwnershipFiltersAndOriginalPermissions() {
        let app = launch()
        let mine = app.segmentedControls.buttons["Mine"]
        XCTAssertTrue(mine.waitForExistence(timeout: 5))
        mine.tap()
        XCTAssertTrue(app.staticTexts["Lemon & herb orzo"].exists)
        XCTAssertFalse(app.staticTexts["Roasted vegetable bowls"].exists)
        XCTAssertTrue(app.staticTexts["You · Only me"].exists)
        app.segmentedControls.buttons["Household"].tap()
        XCTAssertTrue(app.staticTexts["Blueberry overnight oats"].exists)
        XCTAssertFalse(app.staticTexts["Crispy chickpea salad"].exists)
        app.staticTexts["Roasted vegetable bowls"].tap()
        XCTAssertFalse(app.buttons["Edit Recipe"].exists)
        app.buttons["More recipe actions"].tap()
        XCTAssertTrue(app.buttons["Save to My Collection"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Delete Recipe"].exists)
    }
    func testSharingAndDeletionExplainRetainedContent() {
        let app = launch()
        app.staticTexts["Lemon & herb orzo"].tap()
        XCTAssertTrue(app.buttons["Edit Recipe"].waitForExistence(timeout: 5))
        app.buttons["More recipe actions"].tap()
        app.buttons["Make Only Me"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "doesn’t retract prior sharing")).firstMatch.waitForExistence(timeout: 3))
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.55)).tap() }
        app.buttons["More recipe actions"].tap()
        app.buttons["Delete Recipe"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Planned meals keep their saved versions")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "independent copy")).firstMatch.exists)
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.55)).tap() }
    }
    func testLeaveExplainsSuccessorAndBulkSaveStartsOff() {
        let app = launch("--ui-leave")
        let save = app.switches["Save household recipes to my collection"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertEqual(save.value as? String, "0")
        XCTAssertTrue(app.staticTexts["Sam will become the owner of your former household."].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Household move consequences"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    func testInvitationOpensDestinationReviewAndCanCancel() {
        let app = launch("--ui-invite")
        XCTAssertTrue(app.staticTexts["Sam’s household"].waitForExistence(timeout: 5))
        let save = app.switches["Save household recipes to my collection"]
        XCTAssertEqual(save.value as? String, "0")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Lemon & herb orzo"].waitForExistence(timeout: 3))
    }
    func testOwnerCanTransferManually() {
        let app = launch()
        app.buttons["Settings"].tap()
        app.cells.containing(.staticText, identifier: "Household").firstMatch.tap()
        let member = app.cells.containing(.staticText, identifier: "Sam").firstMatch
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        member.swipeLeft()
        XCTAssertFalse(app.buttons["Make Owner"].exists)
        XCTAssertFalse(app.buttons["Remove"].exists)
        app.buttons["Actions for Sam"].tap()
        app.buttons["Make Owner"].tap()
        XCTAssertTrue(app.alerts["Transfer Ownership?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Make Owner"].tap()
        XCTAssertFalse(app.buttons["Delete Household Data"].exists)
    }
    func testInvitationRowOffersSharingAndCopying() {
        let app = launch()
        app.buttons["Settings"].tap()
        app.cells.containing(.staticText, identifier: "Household").firstMatch.tap()
        let invitation = app.buttons["household-invitation"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 5))
        invitation.tap()
        XCTAssertTrue(app.buttons["Share Invitation"].waitForExistence(timeout: 3))
        app.buttons["Copy Code"].tap()
        XCTAssertFalse(app.buttons["Copy Code"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Combined invitation row"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    func testHouseholdDeleteConfirmationAppearance() throws {
        let app = launch()
        app.buttons["Settings"].tap()
        app.cells.containing(.staticText, identifier: "Household").firstMatch.tap()
        let delete = app.buttons["Delete Household Data"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        if !delete.isHittable { app.swipeUp() }
        delete.tap()
        let alert = app.alerts["Delete Household Data?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Delete household confirmation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(try colorCounts(in: alert.buttons["Cancel"].screenshot()).green, 0)
        XCTAssertGreaterThan(try colorCounts(in: alert.buttons["Delete Household Data"].screenshot()).red, 20)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Delete Household Data"].exists)
    }
    func testOwnershipConfirmationAppearance() throws {
        let app = launch()
        app.buttons["Settings"].tap()
        app.cells.containing(.staticText, identifier: "Household").firstMatch.tap()
        app.buttons["Actions for Sam"].tap()
        app.buttons["Make Owner"].tap()
        let alert = app.alerts["Transfer Ownership?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Ownership confirmation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(try colorCounts(in: alert.buttons["Cancel"].screenshot()).green, 0)
        XCTAssertGreaterThan(try colorCounts(in: alert.buttons["Make Owner"].screenshot()).green, 20)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Delete Household Data"].exists)
    }
    func testGroceryConfirmationUsesNeutralCancel() throws {
        let app = launch()
        app.buttons["Groceries"].tap()
        app.buttons["List options"].tap()
        app.buttons["Clear All"].tap()
        let alert = app.alerts["Clear the Entire Grocery List?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertEqual(try colorCounts(in: alert.buttons["Cancel"].screenshot()).green, 0)
        XCTAssertGreaterThan(try colorCounts(in: alert.buttons["Clear All Items"].screenshot()).red, 20)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["List options"].exists)
    }
    func testDestructiveHouseholdRowsHaveNoAccentColoredPixels() throws {
        let app = launch()
        app.buttons["Settings"].tap()
        app.cells.containing(.staticText, identifier: "Household").firstMatch.tap()
        for title in ["Leave Household", "Delete Household Data"] {
            let button = app.buttons[title]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            if !button.isHittable { app.swipeUp() }
            let screenshot = button.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = title
            attachment.lifetime = .keepAlways
            add(attachment)
            let (green, red) = try colorCounts(in: screenshot)
            XCTAssertEqual(green, 0, "\(title) has \(green) green pixels; its icon and title should both be red")
            XCTAssertGreaterThan(red, 20, "\(title) should visibly use the destructive red color")
        }
    }
    private func colorCounts(in screenshot: XCUIScreenshot) throws -> (green: Int, red: Int) {
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var green = 0, red = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
            if g > r + 30 && g > b + 10 { green += 1 }
            if r > g + 30 && r > b + 30 { red += 1 }
        }
        return (green, red)
    }
    func testPlannedMealOpensSavedVersion() {
        let app = launch()
        app.buttons["Meal Plan"].tap()
        app.staticTexts["Lemon & herb orzo"].tap()
        XCTAssertTrue(app.staticTexts["Saved version for this planned meal"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Edit Recipe"].exists)
    }
}
