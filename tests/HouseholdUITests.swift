import XCTest

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
        app.buttons["Make Owner"].tap()
        XCTAssertTrue(app.alerts["Transfer Ownership?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Make Owner"].tap()
        XCTAssertFalse(app.buttons["Delete All Data"].exists)
    }
    func testPlannedMealOpensSavedVersion() {
        let app = launch()
        app.buttons["Meal Plan"].tap()
        app.staticTexts["Lemon & herb orzo"].tap()
        XCTAssertTrue(app.staticTexts["Saved version for this planned meal"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Edit Recipe"].exists)
    }
}
