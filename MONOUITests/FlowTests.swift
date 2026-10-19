import XCTest
import UIKit

@MainActor
final class FlowTests: XCTestCase {
    /// Separate opt-in live test: actual HTTPS/DNS/URLSessionDownloadTask, no URLProtocol.
    /// Uses a foreground session because unsigned hosted simulators reject nsurlsessiond XPC.
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
        UIPasteboard.general.string = "https://fixtures.mono.example/media.png"
        let app = XCUIApplication()
        app.launchArguments = ["--mono-ui-fixtures", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
        let paste = app.buttons["pasteButton"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        XCTAssertTrue(app.navigationBars["Перед сохранением"].waitForExistence(timeout: 10), app.debugDescription)
        let download = app.buttons["downloadButton"]
        for _ in 0..<6 {
            if download.exists && download.isHittable { break }
            app.swipeUp()
        }
        guard download.exists && download.isHittable else { XCTFail(app.debugDescription); return }
        download.tap()
        XCTAssertTrue(app.staticTexts["Сохранено"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["logsButton"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Журнал"].waitForExistence(timeout: 5))
        let logScreenshot = XCTAttachment(screenshot: app.screenshot())
        logScreenshot.name = "MONO-logs-obsidian"
        logScreenshot.lifetime = .keepAlways
        add(logScreenshot)
        app.buttons["closeLogs"].tap()
        app.tabBars.buttons["Коллекция"].tap()
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
