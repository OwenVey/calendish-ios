// UI regression fixture: the installed app must contain Sheet pan lemon chicken.
import XCTest

final class CookModeUITests: XCTestCase {
    func testIngredientSwipeCollapsesSheetAndKeepsStep() {
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish-ios")
        app.launch()
        app.buttons["Recipes"].firstMatch.tap()
        let recipe = app.staticTexts["Sheet Pan Hot Honey Sausage and Gnocchi"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()
        app.buttons["Cook"].tap()
        if app.buttons["Show ingredients"].exists { app.buttons["Show ingredients"].tap() }
        let close = app.buttons["cook-ingredients-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        app.staticTexts["Step 1 of 14"].tap()
        app.buttons["Step 11"].tap()
        let count = app.staticTexts["Step 11 of 14"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            let originalY = count.frame.midY
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let grabber = origin.withOffset(CGVector(dx: app.frame.midX, dy: close.frame.minY - 8))
            let bottom = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.maxY - 20))
            grabber.press(forDuration: 0.1, thenDragTo: bottom)
            // Swiping down collapses the sheet to its header instead of dismissing it.
            let expand = app.buttons["cook-ingredients-expand"]
            XCTAssertTrue(expand.waitForExistence(timeout: 5))
            XCTAssertTrue(count.exists)
            XCTAssertGreaterThan(count.frame.midY, originalY + 100)
            // The collapsed header drags back up from the bottom of the screen.
            let header = origin.withOffset(CGVector(dx: app.frame.midX, dy: expand.frame.minY - 8))
            let middle = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.midY))
            header.press(forDuration: 0.1, thenDragTo: middle)
            XCTAssertTrue(close.waitForExistence(timeout: 5))
        }
        close.tap()
        app.buttons["Close"].firstMatch.tap()
    }

    // Fixture: Sheet Pan Hot Honey Sausage and Gnocchi includes a long timed step.
    func testStepControlsStayAboveIngredientSheet() {
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish-ios")
        app.launch()
        // A persisted session can reopen Cook Mode on launch.
        if app.buttons["Next step"].exists { app.buttons["Close"].firstMatch.tap() }
        app.buttons["Recipes"].firstMatch.tap()
        let recipe = app.staticTexts["Sheet Pan Hot Honey Sausage and Gnocchi"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()
        app.buttons["Cook"].tap()
        if app.buttons["Show ingredients"].exists { app.buttons["Show ingredients"].tap() }
        let close = app.buttons["cook-ingredients-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let next = app.buttons["Next step"]
        let count = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Step ", " of ")).firstMatch
        let anchored = NSPredicate { _, _ in
            let gap = close.frame.minY - next.frame.maxY
            return gap >= 16 && gap <= 48
        }
        expectation(for: anchored, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(count.frame.midY, next.frame.midY, accuracy: 1)
        let controlsY = count.frame.midY
        attach(app, "Step controls above ingredients")

        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Start ", " timer")).firstMatch
        for _ in 0..<13 where !start.exists { next.tap() }
        XCTAssertTrue(start.exists)
        XCTAssertTrue(anchored.evaluate(with: nil), "Timed steps keep the same bottom anchor")
        XCTAssertEqual(count.frame.midY, controlsY, accuracy: 1)
        attach(app, "Timed step above ingredients")
        close.tap()
        let expand = app.buttons["cook-ingredients-expand"]
        let lowered = NSPredicate { _, _ in
            let gap = expand.frame.minY - next.frame.maxY
            return count.frame.midY > controlsY + 100 && gap >= 16 && gap <= 64
        }
        expectation(for: lowered, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        attach(app, "Step controls above collapsed ingredients")
        app.buttons["Close"].firstMatch.tap()
    }

    func testLiveActivityAdvancesCookingStep() {
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish-ios")
        app.launch()
        app.buttons["Recipes"].tap()
        let recipe = app.staticTexts["Sheet Pan Hot Honey Sausage and Gnocchi"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()
        clearCookedToday(app)
        app.buttons["Cook"].tap()
        XCTAssertTrue(app.buttons["cook-ingredients-close"].waitForExistence(timeout: 5))
        app.buttons["cook-ingredients-close"].tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 5"].exists)

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // The compact Live Activity occupies the top-center Dynamic Island on the simulator fixture.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.5)
        let next = springboard.buttons["Next step"]
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
        let activityTitle = springboard.staticTexts["Sheet Pan Hot Honey Sausage and Gnocchi"]
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
            app.buttons["Next step"].tap()
        }
        XCTAssertTrue(timerButton.exists)
        XCUIDevice.shared.press(.home)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.5)
        let startTimer = springboard.buttons["Start timer"]
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
        XCTAssertTrue(app.buttons["Cancel timer"].waitForExistence(timeout: 5))
        app.buttons["Cancel timer"].tap()

        // Finishing from the Live Activity, with no tap in the app, still counts toward cooked history.
        while !app.staticTexts["Step 5 of 5"].exists { app.buttons["Next step"].tap() }
        XCUIDevice.shared.press(.home)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.5)
        let finish = springboard.buttons["Finish cooking"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5), springboard.debugDescription)
        finish.tap()
        app.activate()
        XCTAssertTrue(app.staticTexts["Cooked today"].waitForExistence(timeout: 10))
    }

    /// Removes a mark from earlier today so finishing has something to record.
    private func clearCookedToday(_ app: XCUIApplication) {
        guard app.staticTexts["Cooked today"].waitForExistence(timeout: 3) else { return }
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Last marked cooked")).firstMatch.tap()
        let marked = app.staticTexts["Marked as cooked"].firstMatch
        XCTAssertTrue(marked.waitForExistence(timeout: 5))
        marked.swipeLeft()
        app.buttons["Delete"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Mark cooked today"].waitForExistence(timeout: 5))
    }

    func testIngredientTapKeepsSheetOpen() {
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish-ios")
        app.launch()
        app.buttons["Recipes"].tap()
        let recipe = app.staticTexts["Sheet Pan Hot Honey Sausage and Gnocchi"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()
        app.buttons["Cook"].tap()
        let sheetTitle = app.staticTexts["Ingredients"]
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
        XCTAssertTrue(app.buttons["cook-ingredients-expand"].waitForExistence(timeout: 5))
        instruction.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["cook-ingredients-close"].waitForExistence(timeout: 5))
        XCTAssertTrue(ingredientRow.isSelected)

        let stepCount = app.staticTexts["Step 1 of 5"]
        let originalY = stepCount.frame.midY
        let close = app.buttons["cook-ingredients-close"]
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let grabber = origin.withOffset(CGVector(dx: app.frame.midX, dy: close.frame.minY - 8))
        let bottom = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.maxY - 20))
        grabber.press(forDuration: 0.1, thenDragTo: bottom)
        let collapsed = NSPredicate { _, _ in sheetTitle.exists && app.buttons["cook-ingredients-expand"].exists }
        expectation(for: collapsed, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertGreaterThan(stepCount.frame.midY, originalY + 100)
    }

    func testTimerPausesExtendsAndCancels() {
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish-ios")
        app.launch()
        app.buttons["Recipes"].tap()
        let recipe = app.staticTexts["Sheet Pan Hot Honey Sausage and Gnocchi"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()
        app.buttons["Cook"].tap()
        XCTAssertTrue(app.buttons["cook-ingredients-close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Hide ingredients"].exists)
        attach(app, "Ingredients open")
        app.buttons["cook-ingredients-close"].tap()
        XCTAssertTrue(app.buttons["Show ingredients"].waitForExistence(timeout: 3))
        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Start ", " timer")).firstMatch
        for _ in 0..<8 where !start.exists { app.buttons["Next step"].tap() }
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Always Allow"] where springboard.buttons[label].waitForExistence(timeout: 2) { springboard.buttons[label].tap() }

        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        attach(app, "Running timer")
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 3))
        attach(app, "Paused timer")
        app.buttons["Add 1 minute"].tap()
        app.buttons["Resume"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Paused"].exists)
        app.buttons["Cancel timer"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 3), "Cancelling returns to the start button without confirming")

        // The step count between the arrows doubles as the step picker.
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Step ", " of ")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Step 1"].waitForExistence(timeout: 3))
        attach(app, "Step picker")
        app.buttons["Step 1"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Step 1 of")).firstMatch.waitForExistence(timeout: 3))

        // Finish takes Next's place on the last step without moving the step count.
        let count = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Step ", " of ")).firstMatch
        let countX = count.frame.midX
        for _ in 0..<12 where !app.buttons["Finish cooking"].exists { app.buttons["Next step"].tap() }
        XCTAssertTrue(app.buttons["Finish cooking"].waitForExistence(timeout: 3))
        XCTAssertEqual(count.frame.midX, countX, accuracy: 1)
        attach(app, "Last step")
        app.buttons["Close"].firstMatch.tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testVoiceCommandsKeepTouchControls() {
        let app = XCUIApplication(bundleIdentifier: "owenvey.calendish-ios")
        app.launch()
        app.buttons["Recipes"].tap()
        let recipe = app.staticTexts["Sheet Pan Hot Honey Sausage and Gnocchi"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()
        app.buttons["Cook"].tap()
        XCTAssertTrue(app.buttons["cook-ingredients-close"].waitForExistence(timeout: 5))
        app.buttons["cook-ingredients-close"].tap()
        let firstStep = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Step 1 of")).firstMatch
        XCTAssertTrue(firstStep.exists)
        XCTAssertFalse(app.staticTexts["Listening"].exists, "Cook Mode doesn't listen until voice commands are enabled")

        app.buttons["Voice commands"].tap()
        // The explanation appears before the first activation only.
        let turnOn = app.alerts.buttons["Turn on voice commands"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: 3)); do {
            XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "a TV")).firstMatch.exists)
            turnOn.tap()
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        // Simulators may lack the on-device model; any truthful state is acceptable here.
        let states = ["Listening", "Preparing voice commands", "Voice commands paused"].map { app.staticTexts[$0] }
            + [app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "aren’t available")).firstMatch,
               app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Voice commands need microphone")).firstMatch,
               app.staticTexts["Voice commands stopped unexpectedly"], app.staticTexts["Couldn’t prepare voice commands"]]
        let shown = NSPredicate { _, _ in states.contains { $0.exists } }
        expectation(for: shown, evaluatedWith: nil)
        waitForExpectations(timeout: 15)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Voice commands status"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["Next step"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Step 2 of")).firstMatch.waitForExistence(timeout: 5), "Touch navigation keeps working")
        app.buttons["Previous step"].tap()
        XCTAssertTrue(firstStep.waitForExistence(timeout: 5))
        if app.buttons["Turn off voice commands"].exists { app.buttons["Turn off voice commands"].tap() }
        XCTAssertFalse(app.staticTexts["Listening"].exists, "Stopping ends listening")
        app.buttons["Close"].firstMatch.tap()
    }
}
