import UIKit
import XCTest

final class HouseholdUITests: XCTestCase {
    private func launch(_ argument: String = "--ui-fixture") -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish-household-workflow")
        // UI_LARGE_TEXT (passed as TEST_RUNNER_UI_LARGE_TEXT) reruns a flow at an accessibility text size.
        app.launchArguments = [argument] + (ProcessInfo.processInfo.environment["UI_LARGE_TEXT"] == nil ? [] : ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        app.launch()
        return app
    }
    func testProfilePhotoPickerCanCancelWithoutChangingProfile() {
        let app = launch()
        app.buttons["Settings"].tap()
        app.cells.containing(.staticText, identifier: "Owen").firstMatch.tap()
        let addPhoto = app.buttons["Add profile photo"]
        XCTAssertTrue(addPhoto.waitForExistence(timeout: 5))
        addPhoto.tap()
        app.buttons["Choose a photo"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(addPhoto.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Change profile photo"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native profile photo controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testProfilePhotoCanBeCroppedSavedAndRemoved() {
        let app = launch()
        app.buttons["Settings"].tap()
        app.cells.containing(.staticText, identifier: "Owen").firstMatch.tap()
        app.buttons["Add profile photo"].tap()
        app.buttons["Choose a photo"].tap()
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo,")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5), app.debugDescription)
        photo.tap()
        let use = app.buttons["Use photo"]
        XCTAssertTrue(use.waitForExistence(timeout: 5))
        app.sliders["Photo zoom"].adjust(toNormalizedSliderPosition: 0.4)
        let crop = XCTAttachment(screenshot: app.screenshot())
        crop.name = "Circular profile photo crop"
        crop.lifetime = .keepAlways
        add(crop)
        use.tap()
        let change = app.buttons["Change profile photo"]
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        change.tap()
        app.buttons["Remove photo"].tap()
        XCTAssertTrue(app.buttons["Add profile photo"].waitForExistence(timeout: 5))
    }

    func testOnboardingOnlyAsksForName() {
        let app = launch("--ui-setup")
        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start household"].exists)
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
        XCTAssertFalse(app.buttons["Edit recipe"].exists)
        app.buttons["More recipe actions"].tap()
        XCTAssertTrue(app.buttons["Save to my collection"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Delete recipe"].exists)
    }
    func testSharingAndDeletionExplainRetainedContent() {
        let app = launch()
        app.staticTexts["Lemon & herb orzo"].tap()
        XCTAssertTrue(app.buttons["Edit recipe"].waitForExistence(timeout: 5))
        app.buttons["More recipe actions"].tap()
        app.buttons["Make private"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "keeps a separate copy")).firstMatch.waitForExistence(timeout: 3))
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.55)).tap() }
        app.buttons["More recipe actions"].tap()
        app.buttons["Delete recipe"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Planned meals keep their saved versions")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "separate copy")).firstMatch.exists)
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
        XCTAssertFalse(app.buttons["Make owner"].exists)
        XCTAssertFalse(app.buttons["Remove member"].exists)
        app.buttons["Actions for Sam"].tap()
        app.buttons["Make owner"].tap()
        XCTAssertTrue(app.alerts["Make Sam the owner?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Make owner"].tap()
        XCTAssertFalse(app.buttons["Delete household data"].exists)
    }
    func testInvitationRowOffersSharingAndCopying() {
        let app = launch()
        app.buttons["Settings"].tap()
        app.cells.containing(.staticText, identifier: "Household").firstMatch.tap()
        let invitation = app.buttons["household-invitation"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 5))
        invitation.tap()
        XCTAssertTrue(app.buttons["Share invitation"].waitForExistence(timeout: 3))
        app.buttons["Copy code"].tap()
        XCTAssertFalse(app.buttons["Copy code"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Combined invitation row"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    func testHouseholdDeleteConfirmationAppearance() throws {
        let app = launch()
        app.buttons["Settings"].tap()
        app.cells.containing(.staticText, identifier: "Household").firstMatch.tap()
        let delete = app.buttons["Delete household data"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        if !delete.isHittable { app.swipeUp() }
        delete.tap()
        let alert = app.alerts["Delete household data?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Delete household confirmation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(try colorCounts(in: alert.buttons["Cancel"].screenshot()).green, 0)
        XCTAssertGreaterThan(try colorCounts(in: alert.buttons["Delete household data"].screenshot()).red, 20)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Delete household data"].exists)
    }
    func testOwnershipConfirmationAppearance() throws {
        let app = launch()
        app.buttons["Settings"].tap()
        app.cells.containing(.staticText, identifier: "Household").firstMatch.tap()
        app.buttons["Actions for Sam"].tap()
        app.buttons["Make owner"].tap()
        let alert = app.alerts["Make Sam the owner?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Ownership confirmation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(try colorCounts(in: alert.buttons["Cancel"].screenshot()).green, 0)
        XCTAssertGreaterThan(try colorCounts(in: alert.buttons["Make owner"].screenshot()).green, 20)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Delete household data"].exists)
    }
    func testGroceryConfirmationUsesNeutralCancel() throws {
        let app = launch()
        app.buttons["Groceries"].tap()
        app.buttons["List options"].tap()
        app.buttons["Clear grocery list"].tap()
        let alert = app.alerts["Clear the entire grocery list?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertEqual(try colorCounts(in: alert.buttons["Cancel"].screenshot()).green, 0)
        XCTAssertGreaterThan(try colorCounts(in: alert.buttons["Clear grocery list"].screenshot()).red, 20)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["List options"].exists)
    }
    func testDestructiveHouseholdRowsHaveNoAccentColoredPixels() throws {
        let app = launch()
        app.buttons["Settings"].tap()
        app.cells.containing(.staticText, identifier: "Household").firstMatch.tap()
        for title in ["Leave household", "Delete household data"] {
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
            if g > r + 30, g > b + 10 { green += 1 }
            if r > g + 30, r > b + 30 { red += 1 }
        }
        return (green, red)
    }
    func testPlannedMealOpensSavedVersion() {
        let app = launch()
        app.buttons["Meal plan"].tap()
        app.staticTexts["Lemon & herb orzo"].tap()
        XCTAssertTrue(app.staticTexts["Recipe version saved with this meal"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Edit recipe"].exists)
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testAutoPlanCompactChangeMenu() {
        let app = launch()
        app.buttons["Meal plan"].tap()
        app.buttons["Auto plan"].tap()
        for _ in 0..<4 { app.buttons["Next week"].tap() }
        app.buttons["Suggest dinners"].tap()
        let change = app.buttons["Change dinner"].firstMatch
        change.tap()
        XCTAssertTrue(app.buttons["Remove dinner"].waitForExistence(timeout: 5), "The compact menu opens")
        attachScreenshot(app, named: "Compact change menu")
    }
    func testAutoPlanRecipeOpensAboveProposal() {
        let app = launch()
        app.buttons["Meal plan"].tap()
        app.buttons["Auto plan"].tap()
        app.buttons["Next week"].tap()
        app.buttons["Next week"].tap()
        app.buttons["Next week"].tap()
        app.buttons["Next week"].tap()
        app.buttons["Suggest dinners"].tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Roasted vegetable bowls")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Cook"].waitForExistence(timeout: 5), "The tapped recipe is visible above the proposal")
        attachScreenshot(app, named: "Recipe above auto plan")
        app.navigationBars.buttons["Suggested dinners"].tap()
        XCTAssertTrue(app.buttons["Add to plan"].waitForExistence(timeout: 5), "Back returns to the proposal")
        let servings = app.buttons["4 servings"].firstMatch
        for _ in 0..<8 where !servings.isHittable { app.swipeUp() }
        servings.tap()
        app.steppers.buttons["Increment"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["5 servings"].waitForExistence(timeout: 5), "Servings can be adjusted on demand")
        attachScreenshot(app, named: "Compact servings adjustment")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Kept"].waitForExistence(timeout: 5), "Adjusting servings keeps that dinner")
        let change = app.buttons["Change dinner"].firstMatch
        for _ in 0..<8 where !change.isHittable { app.swipeUp() }
        change.tap()
        XCTAssertTrue(app.buttons["Remove dinner"].exists, "The menu exposes the destructive dinner action")
        attachScreenshot(app, named: "Destructive dinner action")
    }
    func testAutoPlanProposesAdjustsAndAddsDinners() {
        let app = launch()
        app.buttons["Meal plan"].tap()
        app.buttons["Auto plan"].tap()
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 5), "This week is chosen initially")
        attachScreenshot(app, named: "Auto plan days")
        // Go beyond the meal plan's initially loaded four weeks, away from fixture plans.
        for _ in 0..<5 { app.buttons["Next week"].tap() }
        app.buttons["Next week"].tap()
        app.buttons["Suggest dinners"].tap()
        XCTAssertTrue(app.staticTexts["2 dinners suggested · 5 days open"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Auto plan proposal")

        let keep = app.buttons["Keep"].firstMatch
        for _ in 0..<8 where !keep.isHittable || keep.frame.maxY > app.frame.maxY - 80 { app.swipeUp() }
        attachScreenshot(app, named: "Keep control")
        keep.tap()
        XCTAssertTrue(app.buttons["Kept"].waitForExistence(timeout: 5), "Kept dinners are clearly marked")
        for _ in 0..<8 where !app.buttons["Shuffle dinners"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.buttons["Shuffle dinners"].isHittable, "Shuffle has a visible text label")
        app.buttons["Shuffle dinners"].tap()
        XCTAssertTrue(app.alerts["Nothing else to suggest"].waitForExistence(timeout: 5), "A shuffle without alternatives explains itself")
        app.alerts.buttons["OK"].tap()

        let choose = app.buttons["Choose recipe"].firstMatch
        for _ in 0..<8 where !choose.isHittable { app.swipeUp() }
        choose.tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Crispy chickpea salad")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Crispy chickpea salad"].waitForExistence(timeout: 5), "A manual choice can use another category")

        app.buttons["Add to plan"].tap()
        XCTAssertTrue(app.buttons["Auto plan"].waitForExistence(timeout: 5), "Saving closes the proposal and returns to the meal plan")
        XCTAssertFalse(app.buttons["Done"].exists, "There is no extra confirmation screen")
        XCTAssertTrue(app.staticTexts["Roasted vegetable bowls"].isHittable || app.staticTexts["Lemon & herb orzo"].isHittable,
                      "The selected week is revealed without manually scrolling")
        attachScreenshot(app, named: "Auto plan week after saving")
    }
}
