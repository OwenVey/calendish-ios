// UI regression fixture: the installed app must contain Sheet pan lemon chicken.
import XCTest

final class CookModeUITests: XCTestCase {
    func testIngredientTapKeepsSheetOpen() {
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish-ios")
        app.launch()
        app.buttons["Recipes"].tap()
        let recipe = app.staticTexts["Sheet pan lemon chicken"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()
        app.buttons["Start Cooking"].tap()
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
