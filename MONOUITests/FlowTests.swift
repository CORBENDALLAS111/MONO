import XCTest

@MainActor
final class FlowTests: XCTestCase {
    func testAnalyzeSelectDownloadLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--mono-ui-fixtures", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let input = app.textFields["urlInput"].exists ? app.textFields["urlInput"] : app.textViews["urlInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("https://fixtures.mono.invalid/media.png")
        app.buttons["analyzeButton"].tap()
        let download = app.buttons["downloadButton"]
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        download.swipeUp()
        if !download.isHittable { app.swipeUp() }
        download.tap()
        XCTAssertTrue(app.staticTexts["Saved"].firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "media")).firstMatch.waitForExistence(timeout: 5))
    }
    func testUnsupportedSocialShowsHonestError() {
        let app = XCUIApplication()
        app.launchArguments = ["--mono-ui-fixtures", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let input = app.textFields["urlInput"].exists ? app.textFields["urlInput"] : app.textViews["urlInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("https://vm.tiktok.com/abcdef/")
        app.buttons["analyzeButton"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
    }
}
