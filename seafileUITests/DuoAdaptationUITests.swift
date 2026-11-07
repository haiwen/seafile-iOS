import XCTest

/// Walks the signed-in Seafile app on iPhone Duo and captures screenshots for M2 regression.
/// These are screenshot walkthroughs, not assertions: every precondition that is
/// not met (wrong window shape, no signed-in account) skips the test instead of
/// failing it, so a normal test run on any simulator stays green.
/// Outer display: folded (compact width). Inner display: unfolded in DeviceHub first.
final class DuoAdaptationUITests: XCTestCase {

    private var app: XCUIApplication!

    /// Window width that separates the folded outer display from the unfolded inner one.
    private let innerDisplayMinWidth: CGFloat = 520

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.seafile.seafilePro")
        app.launch()
    }

    func testOuterDisplayLibraryFlow() throws {
        try skipUnlessCompactOuterWindow()
        try runLibraryRegressionFlow(screenshotPrefix: "outer")
    }

    func testInnerDisplayLibraryFlow() throws {
        try skipUnlessUnfoldedInnerWindow()
        try runLibraryRegressionFlow(screenshotPrefix: "inner")
    }

    /// Leaves the Pdf library on screen in grid mode so the layout can be checked by eye.
    /// Manual only: it parks the simulator for ten minutes. Run with DUO_MANUAL=1.
    func testShowPdfGrid() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DUO_MANUAL"] != nil,
            "Manual walkthrough; set DUO_MANUAL=1 in the scheme environment to run it."
        )
        let table = try waitForLibraryTable()
        let pdfCell = table.cells.containing(.staticText, identifier: "Pdf").firstMatch
        XCTAssertTrue(pdfCell.waitForExistence(timeout: 8))
        pdfCell.tap()
        let innerTable = app.tables.firstMatch
        XCTAssertTrue(innerTable.waitForExistence(timeout: 20))
        let gridToggle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '网格' OR label CONTAINS[c] 'grid' OR label CONTAINS '列表' OR label CONTAINS[c] 'list'")
        ).firstMatch
        if gridToggle.waitForExistence(timeout: 5) {
            let label = gridToggle.label
            if label.contains("网格") || label.lowercased().contains("grid") {
                gridToggle.tap()
            }
        }
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 8))
        attachScreenshot("pdf-grid")
        // Keep the grid on screen for inspection. Only reached under DUO_MANUAL.
        Thread.sleep(forTimeInterval: 600)
    }

    /// Tabs, search, and settings that are reachable without folding the simulator.
    func testInnerDisplayTabsAndSearch() throws {
        try skipUnlessUnfoldedInnerWindow()
        _ = try waitForLibraryTable()

        let search = app.buttons["directory_search_button"]
        if search.waitForExistence(timeout: 5) {
            search.tap()
            let searchField = app.searchFields.firstMatch
            if searchField.waitForExistence(timeout: 5) {
                searchField.tap()
                searchField.typeText("a")
                Thread.sleep(forTimeInterval: 1)
                let submit = app.keyboards.buttons.matching(
                    NSPredicate(format: "label == 'Search' OR label == '搜索'")
                ).firstMatch
                if submit.exists { submit.tap() }
                Thread.sleep(forTimeInterval: 2)
            }
            let back = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'arrowLeft' OR label == 'Back' OR label == '返回'")
            ).firstMatch
            if back.waitForExistence(timeout: 2) {
                back.tap()
            }
        } else {
            attachScreenshot("inner-search-unavailable")
        }

        let tabs: [(String, String)] = [
            ("label CONTAINS[c] 'Starred' OR label CONTAINS '星标'", "starred"),
            ("label CONTAINS[c] 'Wiki' OR label CONTAINS '知识库'", "wiki"),
            ("label CONTAINS[c] 'Activity' OR label CONTAINS '活动'", "activity"),
            ("label CONTAINS[c] 'Settings' OR label CONTAINS '设置'", "settings"),
            ("label CONTAINS[c] 'Libraries' OR label CONTAINS '资料库'", "libraries"),
        ]
        for (format, name) in tabs {
            let button = app.buttons.matching(NSPredicate(format: format)).firstMatch
            guard button.waitForExistence(timeout: 3) else {
                print("DUO_TAB_ABSENT \(name)")
                continue
            }
            button.tap()
            Thread.sleep(forTimeInterval: 1.5)
            print("DUO_TAB_OPEN \(name)")
        }

        let libraries = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Libraries' OR label CONTAINS '资料库'")
        ).firstMatch
        if libraries.waitForExistence(timeout: 3) { libraries.tap() }
        let more = app.buttons["directory_more_button"]
        if more.waitForExistence(timeout: 3) {
            more.tap()
            Thread.sleep(forTimeInterval: 1)
            print("DUO_MORE_OPEN")
            let cancel = app.buttons.matching(
                NSPredicate(format: "label == 'Cancel' OR label == '取消'")
            ).firstMatch
            if cancel.exists { cancel.tap() }
        }
    }

    // MARK: - Preconditions

    /// Outer cover display is compact width (~466pt); allow slack for future sim changes.
    private func skipUnlessCompactOuterWindow() throws {
        let size = mainWindowSize()
        try XCTSkipIf(
            size.width >= innerDisplayMinWidth,
            "Outer display is inactive (window \(Int(size.width))×\(Int(size.height)) pt). Fold in DeviceHub to run this."
        )
        attachScreenshot("outer-00-window-\(Int(size.width))x\(Int(size.height))")
    }

    /// Unfolded inner display is regular width (~669pt class).
    private func skipUnlessUnfoldedInnerWindow() throws {
        let size = mainWindowSize()
        try XCTSkipIf(
            size.width < innerDisplayMinWidth,
            "Inner display is inactive (window \(Int(size.width))×\(Int(size.height)) pt). Unfold in DeviceHub to run this."
        )
        attachScreenshot("inner-00-window-\(Int(size.width))x\(Int(size.height))")
    }

    private func mainWindowSize() -> CGSize {
        let window = app.windows.firstMatch
        _ = window.waitForExistence(timeout: 15)
        return window.frame.size
    }

    /// The library root table. Absent when no account is signed in on the simulator.
    private func waitForLibraryTable() throws -> XCUIElement {
        let table = app.tables.firstMatch
        try XCTSkipUnless(
            table.waitForExistence(timeout: 20),
            "No library table; sign an account in on the booted simulator first."
        )
        return table
    }

    // MARK: - Library flow

    private func runLibraryRegressionFlow(screenshotPrefix: String) throws {
        let table = try waitForLibraryTable()
        attachScreenshot("\(screenshotPrefix)-01-library-root")

        let cellCount = table.cells.count
        XCTAssertGreaterThan(cellCount, 0, "Expected at least one library row, got \(cellCount)")

        let pdfCell = table.cells.containing(.staticText, identifier: "Pdf").firstMatch
        let target = pdfCell.exists ? pdfCell : table.cells.element(boundBy: min(1, cellCount - 1))
        XCTAssertTrue(target.exists, "Need a library row to open")
        target.tap()

        let innerTable = app.tables.firstMatch
        XCTAssertTrue(innerTable.waitForExistence(timeout: 20), "Folder/file list should appear after opening a library")
        attachScreenshot("\(screenshotPrefix)-02-inside-library")

        let gridToggle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'grid' OR label CONTAINS '网格' OR label CONTAINS[c] 'list' OR label CONTAINS '列表'")
        ).firstMatch
        if gridToggle.waitForExistence(timeout: 5) {
            gridToggle.tap()
            attachScreenshot("\(screenshotPrefix)-03-grid-view")
            let collection = app.collectionViews.firstMatch
            XCTAssertTrue(collection.waitForExistence(timeout: 5), "Grid collection view should appear")
        }

        let fileCell = innerTable.cells.element(boundBy: 0)
        if fileCell.exists {
            fileCell.press(forDuration: 1.0)
            attachScreenshot("\(screenshotPrefix)-04-multi-select")
            let toolbarButton = app.otherElements["profile_properties_toolbar_button"].firstMatch
            _ = toolbarButton.waitForExistence(timeout: 5)
        }

        if innerTable.cells.count > 0 {
            innerTable.cells.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 2)
            attachScreenshot("\(screenshotPrefix)-05-after-tap-item")
        }
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
