import XCTest

final class GrocerySearchUITests: XCTestCase {
    func testPastedListCanBeReviewedWithoutAddingItems() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish")
        app.launch()
        XCTAssertTrue(app.buttons["Groceries"].waitForExistence(timeout: 10))
        app.buttons["Groceries"].tap()
        app.buttons["List options"].tap()
        app.buttons["Paste grocery list"].tap()
        let editor = app.textViews["Grocery list to paste"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["Review items"].isEnabled)
        editor.tap()
        editor.typeText("- Milk\n\n- 2 eggs\n[ ] Bread")
        app.buttons["Review items"].tap()
        XCTAssertTrue(app.buttons["Add 3 items"].waitForExistence(timeout: 5), app.debugDescription)
        // The household list remains in the accessibility tree behind the sheet.
        let review = app.collectionViews.containing(NSPredicate(format: "value == %@", "Milk")).firstMatch
        let fields = review.textFields.matching(identifier: "Grocery item")
        XCTAssertEqual(fields.count, 3, app.debugDescription)
        XCTAssertEqual(fields.element(boundBy: 0).value as? String, "Milk")
        XCTAssertEqual(fields.element(boundBy: 1).value as? String, "2 eggs")
        fields.element(boundBy: 2).tap()
        fields.element(boundBy: 2).typeText(" rolls")
        let edited = fields.element(boundBy: 2).value as? String ?? ""
        XCTAssertTrue(edited.contains("Bread") && edited.contains("rolls"), "The reviewed item should retain typed edits")
        fields.element(boundBy: 0).swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Add 2 items"].exists, app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Pasted groceries reviewed and edited"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.navigationBars["Review items"].buttons.element(boundBy: 0).tap()
        app.buttons["Cancel"].tap()
        app.buttons["Discard list"].tap()
        XCTAssertTrue(app.buttons["List options"].waitForExistence(timeout: 5))
    }

    func testSearchClosesWithOneTapAndStaysClosed() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish")
        app.launch()
        let groceries = app.buttons["Groceries"]
        XCTAssertTrue(groceries.waitForExistence(timeout: 10), app.debugDescription)
        groceries.tap()
        let options = app.buttons["List options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        let optionsFrame = options.frame
        for cycle in 0..<3 {
            let openSearch = app.searchFields.firstMatch
            XCTAssertTrue(openSearch.waitForExistence(timeout: 5), app.debugDescription)
            openSearch.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
            let searchField = app.searchFields.firstMatch
            let searchValue = searchField.value as? String ?? ""
            XCTAssertTrue(searchValue.isEmpty || searchValue == searchField.placeholderValue)
            let all = app.buttons["All"]
            XCTAssertTrue(all.waitForExistence(timeout: 3))
            XCTAssertTrue(all.isSelected)
            if cycle == 1 {
                app.searchFields.firstMatch.typeText("olive")
            } else if cycle == 2 {
                app.buttons["Checked"].tap()
            }
            let cancel = app.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "close", "cancel")).firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 3), app.debugDescription)
            cancel.tap()
            let afterClose = XCTAttachment(screenshot: app.screenshot())
            afterClose.name = "After one search-close tap"
            afterClose.lifetime = .keepAlways
            add(afterClose)
            let closed = NSPredicate { _, _ in
                !app.keyboards.firstMatch.exists && !app.buttons["Checked"].exists
            }
            expectation(for: closed, evaluatedWith: nil)
            waitForExpectations(timeout: 5)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Add “")).count, 0)
            let reopened = expectation(for: NSPredicate { _, _ in app.keyboards.firstMatch.exists }, evaluatedWith: nil)
            reopened.isInverted = true
            waitForExpectations(timeout: 2)
            XCTAssertEqual(options.frame.midX, optionsFrame.midX, accuracy: 1)
            XCTAssertEqual(options.frame.midY, optionsFrame.midY, accuracy: 1)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Groceries search dismissed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
