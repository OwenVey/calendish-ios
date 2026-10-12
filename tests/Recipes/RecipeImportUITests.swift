// UI checks for imports and recipe-book regressions against the installed, signed-in app.
// Fixture: Weeknight Beef Tacos. Imported recipes are reviewed and canceled; nothing is saved.
import XCTest

final class RecipeImportUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private let app = XCUIApplication(bundleIdentifier: "owenvey.calendish")

    func testIngredientsOnlyImportCanBeSaved() {
        importText("Weeknight Garlic Noodles\nIngredients:\n200g noodles\n4 cloves garlic\n")
        XCTAssertEqual(app.textFields["Recipe title"].value as? String, "Weeknight Garlic Noodles")
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "200g noodles")).firstMatch.exists)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "4 cloves garlic")).firstMatch.exists)
        XCTAssertTrue(saveButton.isEnabled, "A title and ingredients are enough to save")
        cancelAndCheckNothingSaved("Weeknight Garlic Noodles")
    }

    func testInstructionsOnlyImportCanBeSaved() {
        importText("Lemon Butter Pasta\nMethod:\n1. Boil the pasta in salted water.\n2. Toss it with lemon zest and butter.\n")
        XCTAssertEqual(app.textFields["Recipe title"].value as? String, "Lemon Butter Pasta")
        // Multiline SwiftUI fields can be exposed as TextField or TextView across simulator versions.
        let step = app.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "Boil the pasta in salted water.")).firstMatch
        if !step.exists { app.swipeUp() }
        XCTAssertTrue(step.waitForExistence(timeout: 5), "The imported instruction remains editable")
        XCTAssertTrue(saveButton.isEnabled, "A title and instructions are enough to save")

        // Without a title, there's nothing to save it as.
        app.swipeDown()
        let title = app.textFields["Recipe title"]
        title.tap()
        title.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        title.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertFalse(saveButton.isEnabled, "A recipe needs a title")
        app.buttons["Cancel"].firstMatch.tap()
        if app.buttons["Discard changes"].waitForExistence(timeout: 3) { app.buttons["Discard changes"].tap() }
        XCTAssertTrue(app.buttons["New recipe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Lemon Butter Pasta"].exists)
    }

    func testSearchSurvivesLayoutChangesAndReturningFromSettings() {
        app.launch()
        app.tabBars.buttons["Recipes"].firstMatch.tap()
        for layout in ["Grid", "List"] {
            app.buttons["View, sort, and filter"].tap()
            app.buttons[layout].tap()
            XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "Search remains available in \(layout)")
            app.tabBars.buttons["Settings"].tap()
            app.tabBars.buttons["Recipes"].tap()
            XCTAssertTrue(app.searchFields.firstMatch.exists)
        }
        app.tabBars.buttons["Groceries"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    }

    func testRatingLabelsAndTimerStatusAcrossSteps() {
        app.launch()
        app.tabBars.buttons["Recipes"].firstMatch.tap()
        let recipe = app.staticTexts["Weeknight Beef Tacos"].firstMatch
        XCTAssertTrue(recipe.waitForExistence(timeout: 5))
        recipe.tap()
        for star in 1...5 {
            XCTAssertTrue(app.buttons[star == 1 ? "Rate 1 star" : "Rate \(star) stars"].exists)
        }
        app.buttons["Cook"].tap()
        // A kept cooking session may resume on a later step.
        let previous = app.buttons["Previous step"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        for _ in 0..<5 where previous.isEnabled { previous.tap() }
        app.buttons["Start 4 min timer"].tap()
        app.buttons["Next step"].tap()
        let status = app.buttons["Cook Mode running timers"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Step 1 timer"))
        status.tap()
        XCTAssertTrue(app.buttons["Pause step 1 timer"].exists)
        app.buttons["Cancel step 1 timer"].tap()
        XCTAssertFalse(status.exists)
        app.buttons["Close"].firstMatch.tap()
        app.navigationBars.buttons["Recipes"].tap()
    }

    func testInvalidLinkKeepsItsFormAndExplainsRecovery() {
        app.launch()
        app.tabBars.buttons["Recipes"].firstMatch.tap()
        app.buttons["New recipe"].tap()
        app.buttons["Import from link"].tap()
        let link = app.textFields["Recipe link"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        link.typeText("not-a-url")
        XCTAssertTrue(app.buttons["Import"].isEnabled, "Typing a link enables import before validation")
        // Submit through the URL field’s Go action.
        link.typeText("\n")
        let error = app.staticTexts["Recipe import error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("https://"))
        XCTAssertTrue(app.navigationBars["Import from link"].exists)
        XCTAssertEqual(link.value as? String, "not-a-url")
        app.buttons["Clear"].tap()
        XCTAssertFalse(error.exists)
        app.buttons["Cancel"].firstMatch.tap()
    }

    private var saveButton: XCUIElement { app.navigationBars.buttons["Save"] }

    private func importText(_ text: String) {
        app.launch()
        let recipesTab = app.tabBars.buttons["Recipes"].firstMatch
        XCTAssertTrue(recipesTab.waitForExistence(timeout: 10))
        if !recipesTab.isSelected { recipesTab.tap() }
        XCTAssertTrue(app.buttons["New recipe"].waitForExistence(timeout: 10))
        app.buttons["New recipe"].tap()
        app.buttons["Paste recipe text"].tap()
        // SwiftUI multiline fields use either editable type across simulator versions.
        let field = app.descendants(matching: .any).matching(NSPredicate(
            format: "(label == %@ OR label == %@) AND (elementType == %d OR elementType == %d)",
            "Recipe text", "Paste a recipe", XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue)).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText(text)
        app.buttons["Import"].tap()
        XCTAssertTrue(app.textFields["Recipe title"].waitForExistence(timeout: 60), "The imported draft opens in the editor")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func cancelAndCheckNothingSaved(_ title: String) {
        app.buttons["Cancel"].firstMatch.tap()
        if app.buttons["Discard changes"].waitForExistence(timeout: 3) { app.buttons["Discard changes"].tap() }
        XCTAssertTrue(app.buttons["New recipe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[title].exists, "Cancelling doesn't save the recipe")
    }
}
