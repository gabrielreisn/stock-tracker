import XCTest

final class PhoneTests: XCTestCase {
    func testCymbaIdentityAndFourTabsInLightAndDarkMode() {
        let app = XCUIApplication()
        for appearance in ["light", "dark"] {
            app.launchArguments = ["-theme", appearance, "-AppleLanguages", "(en)"]
            app.launch()
            XCTAssertTrue(app.staticTexts["overview-title"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label), ["Overview", "Investments", "Finances", "Settings"])
            for (tab, titleID) in [("Overview", "overview-title"), ("Investments", "investments-title"), ("Finances", "finances-title"), ("Settings", "settings-title")] {
                app.tabBars.buttons[tab].tap()
                XCTAssertTrue(app.staticTexts[titleID].waitForExistence(timeout: 5))
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Cymba \(tab) \(appearance)"; screenshot.lifetime = .keepAlways; add(screenshot)
            }
            app.terminate()
        }
    }

    func testCategoryDragPersistsAndStillOpensEditor() {
        let app = XCUIApplication()
        app.launch()
        openCategories(app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "category-"))
        XCTAssertGreaterThanOrEqual(rows.count, 2)
        let firstID = rows.element(boundBy: 0).identifier
        let secondID = rows.element(boundBy: 1).identifier
        let firstName = rows.element(boundBy: 0).label
        let secondName = rows.element(boundBy: 1).label
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Category drag handles"; before.lifetime = .keepAlways; add(before)
        let source = app.buttons["Reorder " + secondName]
        let target = app.buttons["Reorder " + firstName]
        XCTAssertTrue(source.isHittable)
        XCTAssertTrue(target.isHittable)
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.5)))
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            rows.element(boundBy: 0).identifier == secondID
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 5), .completed)
        // Opening the editor also gives the serialized background write time to finish.
        app.buttons[secondID].tap()
        XCTAssertTrue(app.staticTexts["category-editor-title"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.terminate(); app.launch()
        openCategories(app)
        XCTAssertEqual(rows.element(boundBy: 0).identifier, secondID)
        XCTAssertEqual(rows.element(boundBy: 1).identifier, firstID)
    }

    private func openCategories(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Finances"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Finances"].tap()
        app.buttons["Categories & limits"].tap()
        XCTAssertTrue(app.navigationBars["Categories & limits"].waitForExistence(timeout: 5))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "category-"))
        for _ in 0..<6 where rows.count < 2 || !rows.element(boundBy: 1).isHittable { app.swipeUp() }
    }

    func testPhoneNavigationAndManualExpense() {
        let app = XCUIApplication()
        let expenseName = "Swift Test " + String(UUID().uuidString.prefix(8))
        app.launch()
        XCTAssertTrue(app.staticTexts["overview-title"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Investments"].tap()
        app.buttons["Bonds"].tap()
        XCTAssertTrue(app.navigationBars["Bonds"].waitForExistence(timeout: 5))
        app.buttons["Add bond"].tap()
        XCTAssertTrue(app.textFields["bondIssuer"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["Finances"].tap()
        app.buttons["Expenses"].tap()
        app.buttons["add-expense"].tap()
        let store = app.textFields["Store"]
        XCTAssertTrue(store.waitForExistence(timeout: 5))
        store.tap(); store.typeText(expenseName)
        let amount = app.textFields["Amount"]
        amount.tap(); amount.typeText("42")
        app.buttons["Save"].tap()
        let search = app.textFields["Search store or item"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText(expenseName)
        app.keyboards.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts[expenseName].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.tabBars.buttons["Finances"].tap(); app.buttons["Expenses"].tap()
        app.textFields["Search store or item"].tap(); app.textFields["Search store or item"].typeText(expenseName)
        app.keyboards.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts[expenseName].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["settings-title"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !app.buttons["AI"].isHittable { app.swipeUp() }
        app.buttons["AI"].tap()
        XCTAssertTrue(app.navigationBars["AI"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "iPhone Settings"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
