// UI regression fixture: the installed app must contain Sheet pan lemon chicken.
import XCTest

final class CookModeUITests: XCTestCase {
    func testLiveActivityAdvancesCookingStep() {
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish-ios")
        app.launch()
        app.buttons["Recipes"].tap()
        let recipe = app.staticTexts["Sheet pan lemon chicken"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()
        app.buttons["Cook"].tap()
        XCTAssertTrue(app.buttons["cook-ingredients-close"].waitForExistence(timeout: 5))
        app.buttons["cook-ingredients-close"].tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 5"].exists)

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // The compact Live Activity occupies the top-center Dynamic Island on the simulator fixture.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.5)
        let next = springboard.buttons["Next Step"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), springboard.debugDescription)
        let activityScreenshot = XCTAttachment(screenshot: springboard.screenshot())
        activityScreenshot.name = "Expanded recipe Live Activity"
        activityScreenshot.lifetime = .keepAlways
        add(activityScreenshot)
        next.tap()
        app.activate()
        XCTAssertTrue(app.staticTexts["Step 2 of 5"].waitForExistence(timeout: 5))
        // Reopening a persisted Live Activity must restore its step and thumbnail after a cold launch.
        app.terminate()
        app.launch()
        XCUIDevice.shared.press(.home)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.5)
        let activityTitle = springboard.staticTexts["Sheet pan lemon chicken"]
        XCTAssertTrue(activityTitle.waitForExistence(timeout: 5))
        activityTitle.tap()
        XCTAssertTrue(app.buttons["cook-ingredients-close"].waitForExistence(timeout: 5))
        app.buttons["cook-ingredients-close"].tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 5"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // Find a timed step in the fixture, then start its timer from the Live Activity.
        let timerButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Start ", " timer")).firstMatch
        for _ in 0..<3 {
            if timerButton.exists { break }
            app.buttons["Next Step"].tap()
        }
        XCTAssertTrue(timerButton.exists)
        XCUIDevice.shared.press(.home)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.5)
        let startTimer = springboard.buttons["Start Timer"]
        XCTAssertTrue(startTimer.waitForExistence(timeout: 5))
        startTimer.tap()
        let timerScreenshot = XCTAttachment(screenshot: springboard.screenshot())
        timerScreenshot.name = "Recipe Live Activity with running timer"
        timerScreenshot.lifetime = .keepAlways
        add(timerScreenshot)
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.01))
        let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        if springboard.buttons["Allow"].exists { springboard.buttons["Allow"].tap() }
        if springboard.buttons["Always Allow"].exists { springboard.buttons["Always Allow"].tap() }
        let lockScreenScreenshot = XCTAttachment(screenshot: springboard.screenshot())
        lockScreenScreenshot.name = "Lock Screen recipe Live Activity"
        lockScreenScreenshot.lifetime = .keepAlways
        add(lockScreenScreenshot)
        app.activate()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.buttons["Close"].tap()
    }

    func testIngredientTapKeepsSheetOpen() {
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish-ios")
        app.launch()
        app.buttons["Recipes"].tap()
        let recipe = app.staticTexts["Sheet pan lemon chicken"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()
        app.buttons["Cook"].tap()
        let sheetTitle = app.staticTexts["All Ingredients"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 5))
        let instruction = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Heat the oven to 425")).firstMatch
        XCTAssertTrue(instruction.waitForExistence(timeout: 5))
        instruction.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        let ingredientRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "baby potatoes")).firstMatch
        // Verify the tap reached the matching ingredient, as well as preserving the sheet.
        let staysOpen = NSPredicate { _, _ in sheetTitle.exists && app.buttons["cook-ingredients-close"].isHittable && ingredientRow.isSelected }
        expectation(for: staysOpen, evaluatedWith: nil)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(app.popovers.count, 0)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["cook-ingredients-close"].tap()
        XCTAssertFalse(sheetTitle.exists)
        instruction.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(ingredientRow.isSelected)

        let stepCount = app.staticTexts["Step 1 of 5"]
        let originalY = stepCount.frame.midY
        let close = app.buttons["cook-ingredients-close"]
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let grabber = origin.withOffset(CGVector(dx: app.frame.midX, dy: close.frame.minY - 8))
        let bottom = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.maxY - 20))
        grabber.press(forDuration: 0.1, thenDragTo: bottom)
        let dismissed = NSPredicate { _, _ in !sheetTitle.exists }
        expectation(for: dismissed, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertGreaterThan(stepCount.frame.midY, originalY + 100)
    }
}
