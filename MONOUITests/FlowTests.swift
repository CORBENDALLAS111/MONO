import XCTest

@MainActor
final class FlowTests: XCTestCase {
    /// Separate opt-in live test: uses production HTTPS/DNS/background URLSession, no URLProtocol.
    /// NASA Blue Marble, educational verification; NASA source acknowledged, no endorsement.
    /// https://www.nasa.gov/nasa-brand-center/images-and-media/
    func testLiveAuthorizedDirectImageDownload() {
        let app = XCUIApplication()
        app.launchArguments = ["--mono-live-smoke", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let input = app.textFields["urlInput"].exists ? app.textFields["urlInput"] : app.textViews["urlInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57723/globe_west_540.jpg")
        app.buttons["analyzeButton"].tap()
        guard app.navigationBars["Before you save"].waitForExistence(timeout: 35) else { XCTFail(app.debugDescription); return }
        let download = app.buttons["downloadButton"]
        for _ in 0..<6 {
            if download.exists && download.isHittable { break }
            app.swipeUp()
        }
        guard download.exists && download.isHittable else { XCTFail(app.debugDescription); return }
        download.tap()
        XCTAssertTrue(app.staticTexts["Saved"].firstMatch.waitForExistence(timeout: 60), app.debugDescription)
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "globe_west_540")).firstMatch.waitForExistence(timeout: 5))
    }
    func testHomeInBothThemes() {
        for theme in ["obsidian", "porcelain"] {
            let app = XCUIApplication()
            app.launchArguments = ["--mono-ui-fixtures", "-appearance", theme, "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
            app.launch()
            XCTAssertTrue(app.buttons["analyzeButton"].waitForExistence(timeout: 5))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "MONO-home-" + theme
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }
    func testAnalyzeSelectDownloadLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--mono-ui-fixtures", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let input = app.textFields["urlInput"].exists ? app.textFields["urlInput"] : app.textViews["urlInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("https://fixtures.mono.example/media.png")
        app.buttons["analyzeButton"].tap()
        XCTAssertTrue(app.navigationBars["Before you save"].waitForExistence(timeout: 10), app.debugDescription)
        let download = app.buttons["downloadButton"]
        for _ in 0..<6 {
            if download.exists && download.isHittable { break }
            app.swipeUp()
        }
        guard download.exists && download.isHittable else { XCTFail(app.debugDescription); return }
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
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "authorized server")).firstMatch.exists)
    }
}
