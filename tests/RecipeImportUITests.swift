// UI checks for partial recipe imports. They review the imported draft and cancel, so nothing is saved.
import XCTest

final class RecipeImportUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "owenvey.calendish-ios")

    func testIngredientsOnlyImportCanBeSaved() {
        importText("Weeknight Garlic Noodles\nIngredients:\n200g noodles\n4 cloves garlic\n")
        XCTAssertEqual(app.textFields["Recipe Title"].value as? String, "Weeknight Garlic Noodles")
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "200g noodles")).firstMatch.exists)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "4 cloves garlic")).firstMatch.exists)
        XCTAssertTrue(saveButton.isEnabled, "A title and ingredients are enough to save")
        cancelAndCheckNothingSaved("Weeknight Garlic Noodles")
    }

    func testInstructionsOnlyImportCanBeSaved() {
        importText("Lemon Butter Pasta\nMethod:\n1. Boil the pasta in salted water.\n2. Toss it with lemon zest and butter.\n")
        XCTAssertEqual(app.textFields["Recipe Title"].value as? String, "Lemon Butter Pasta")
        let step = app.textViews.matching(NSPredicate(format: "value == %@", "Boil the pasta in salted water.")).firstMatch
        XCTAssertTrue(step.exists)
        XCTAssertTrue(saveButton.isEnabled, "A title and instructions are enough to save")

        // Without a title, there's nothing to save it as.
        let title = app.textFields["Recipe Title"]
        title.tap()
        title.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        title.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertFalse(saveButton.isEnabled, "A recipe needs a title")
        app.buttons["Cancel"].firstMatch.tap()
        if app.buttons["Discard Changes"].waitForExistence(timeout: 3) { app.buttons["Discard Changes"].tap() }
        XCTAssertTrue(app.buttons["New Recipe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Lemon Butter Pasta"].exists)
    }

    private var saveButton: XCUIElement { app.navigationBars.buttons["Save"] }

    private func importText(_ text: String) {
        app.launch()
        app.buttons["Recipes"].tap()
        XCTAssertTrue(app.buttons["New Recipe"].waitForExistence(timeout: 10))
        app.buttons["New Recipe"].tap()
        app.buttons["Paste Recipe Text"].tap()
        let field = app.textViews["Recipe text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        app.buttons["Import"].tap()
        XCTAssertTrue(app.textFields["Recipe Title"].waitForExistence(timeout: 60), "The imported draft opens in the editor")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func cancelAndCheckNothingSaved(_ title: String) {
        app.buttons["Cancel"].firstMatch.tap()
        if app.buttons["Discard Changes"].waitForExistence(timeout: 3) { app.buttons["Discard Changes"].tap() }
        XCTAssertTrue(app.buttons["New Recipe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[title].exists, "Cancelling doesn't save the recipe")
    }
}
