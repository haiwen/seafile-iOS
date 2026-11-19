import XCTest

/// Walks the signed-in Seafile app on iPhone Duo and captures screenshots for M2 regression.
/// Walkthroughs capture layout evidence; the selection test also asserts boundaries
/// and cleanup. Missing accounts or a different display pose skip relevant tests.
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

    /// Exercise the form without creating a library on the signed-in server.
    func testNewLibraryDialogLayoutAndEncryption() throws {
        let contentFrame = try waitForLibraryTable().frame
        try openNewLibraryDialog()
        let panel = app.otherElements["new_library_dialog"]
        let name = app.textFields["new_library_name"]
        let toggle = app.switches["new_library_encrypt"]
        let cancel = app.buttons["new_library_cancel"]
        let confirm = app.buttons["new_library_confirm"]
        defer { if cancel.exists { cancel.tap() } }

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "Enable the simulator software keyboard")
        name.typeText("Duo layout check")
        assertNewLibraryPanel(panel, inside: contentFrame, above: keyboard)
        XCTAssertTrue(toggle.isHittable, "The system rail must not cover the encryption switch")
        XCTAssertLessThanOrEqual(toggle.frame.maxX, contentFrame.maxX + 1)

        toggle.tap()
        let password = app.secureTextFields["new_library_password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.typeText("duo-test-1234")
        let confirmation = app.secureTextFields["new_library_password_confirmation"]
        confirmation.tap()
        confirmation.typeText("duo-test-1234")
        assertNewLibraryPanel(panel, inside: contentFrame, above: keyboard)
        let viewport = app.scrollViews["new_library_form"].frame
        XCTAssertGreaterThanOrEqual(confirmation.frame.minY, viewport.minY - 1)
        XCTAssertLessThanOrEqual(confirmation.frame.maxY, viewport.maxY + 1)
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(confirm.isHittable, "Actions stay visible while the form scrolls")
        attachScreenshot("new-library-encrypted")

        // The switch may have scrolled above the viewport on the outer display.
        app.scrollViews["new_library_form"].swipeDown()
        toggle.tap()
        XCTAssertFalse(password.exists)
        XCTAssertEqual(name.value as? String, "Duo layout check")
        assertNewLibraryPanel(panel, inside: contentFrame, above: keyboard)
        attachScreenshot("new-library-unencrypted")
    }

    func testNewLibraryValidationAndCancel() throws {
        _ = try waitForLibraryTable()
        try openNewLibraryDialog()
        app.buttons["new_library_confirm"].tap()
        let validationAlert = app.alerts.firstMatch
        XCTAssertTrue(validationAlert.waitForExistence(timeout: 5))
        validationAlert.buttons.firstMatch.tap()
        XCTAssertTrue(app.otherElements["new_library_dialog"].exists)
        app.buttons["new_library_cancel"].tap()
        XCTAssertTrue(app.otherElements["new_library_dialog"].waitForNonExistence(timeout: 5))

        try openNewLibraryDialog()
        XCTAssertTrue(app.textFields["new_library_name"].isHittable)
        app.buttons["new_library_cancel"].tap()
    }

    private func openNewLibraryDialog() throws {
        app.buttons["directory_more_button"].tap()
        let createLibrary = app.buttons.matching(NSPredicate(
            format: "label == 'New Library' OR label == '新建资料库'"
        )).firstMatch
        XCTAssertTrue(createLibrary.waitForExistence(timeout: 5))
        createLibrary.tap()
        XCTAssertTrue(app.otherElements["new_library_dialog"].waitForExistence(timeout: 5))
    }

    private func assertNewLibraryPanel(_ panel: XCUIElement, inside contentFrame: CGRect,
                                       above keyboard: XCUIElement,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(panel.frame.minX, contentFrame.minX - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(panel.frame.maxX, contentFrame.maxX + 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(panel.frame.minY, app.windows.firstMatch.frame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(panel.frame.maxY, keyboard.frame.minY + 1, file: file, line: line)
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
        try runTabsAndSearch(screenshotPrefix: "inner")
    }

    /// Run in either Duo pose, explicitly keeping the main flow in portrait.
    func testPortraitTabsAndSearch() throws {
        XCUIDevice.shared.orientation = .portrait
        let size = mainWindowSize()
        XCTAssertLessThan(size.width, size.height)
        try runTabsAndSearch(screenshotPrefix: "portrait-\(Int(size.width))x\(Int(size.height))")
    }

    private func runTabsAndSearch(screenshotPrefix: String) throws {
        _ = try waitForLibraryTable()
        attachScreenshot("\(screenshotPrefix)-libraries")

        let search = app.buttons["directory_search_button"]
        if search.waitForExistence(timeout: 5) {
            search.tap()
            let searchField = app.searchFields.firstMatch
            if searchField.waitForExistence(timeout: 5) {
                searchField.tap()
                searchField.typeText("a")
                attachScreenshot("\(screenshotPrefix)-search-keyboard")
                Thread.sleep(forTimeInterval: 1)
                let submit = app.keyboards.buttons.matching(
                    NSPredicate(format: "label == 'Search' OR label == '搜索'")
                ).firstMatch
                if submit.exists { submit.tap() }
                Thread.sleep(forTimeInterval: 2)
                attachScreenshot("\(screenshotPrefix)-search-results")
            }
            let back = app.buttons.matching(
                NSPredicate(format: "identifier == 'navigation_back_button' OR label CONTAINS 'arrowLeft' OR label == 'Back' OR label == '返回'")
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
            attachScreenshot("\(screenshotPrefix)-\(name)")
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
            attachScreenshot("\(screenshotPrefix)-more")
            print("DUO_MORE_OPEN")
            let cancel = app.buttons.matching(
                NSPredicate(format: "label == 'Cancel' OR label == '取消'")
            ).firstMatch
            if cancel.exists { cancel.tap() }
        }
    }

    /// Selection must not cover the system rail, and must clean up on exit.
    /// Run in either Duo pose with an authenticated, nonempty test library.
    func testSelectionToolbarStaysInsideContent() throws {
        let table = try openAdaptationLibrary()
        let entry = table.cells.firstMatch
        try XCTSkipUnless(entry.waitForExistence(timeout: 10), "The test library has no entries")
        entry.press(forDuration: 1)
        let panel = app.descendants(matching: .any)["directory_selection_toolbar"]
        let hasPanel = panel.waitForExistence(timeout: 5)
        XCTAssertTrue(hasPanel)
        XCTAssertGreaterThan(panel.frame.width, 0)
        XCTAssertGreaterThanOrEqual(panel.frame.minX, table.frame.minX - 1)
        XCTAssertLessThanOrEqual(panel.frame.maxX, table.frame.maxX + 1)
        let settings = app.buttons.matching(
            NSPredicate(format: "label == 'Settings' OR label == '设置'")
        ).firstMatch
        if settings.exists {
            XCTAssertTrue(settings.isHittable, "Selection must leave system tabs reachable")
            let overlap = settings.frame.intersection(panel.frame)
            XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 1,
                          "Selection panel overlaps the system tab")
        }
        let selectAll = app.buttons["directory_select_all_button"]
        XCTAssertTrue(selectAll.isHittable)
        selectAll.tap()
        XCTAssertTrue(selectAll.isHittable, "Select None remains reachable after selecting all")
        attachScreenshot("selection-safe-area")
        let close = app.buttons["directory_exit_selection_button"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        let removed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: panel)
        wait(for: [removed], timeout: 5)
        XCTAssertTrue(app.buttons["directory_more_button"].isHittable)
        // A second session catches stale dismissal completions and selection state.
        entry.press(forDuration: 1)
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isHittable)
        close.tap()
    }

    /// A page change must update the system title as well as the displayed image.
    func testGalleryTitleUpdatesAfterThumbnailSelection() throws {
        let table = try openAdaptationLibrary()
        let imageLabels = table.staticTexts.matching(NSPredicate(
            format: "label ENDSWITH[c] '.jpg' OR label ENDSWITH[c] '.jpeg' OR label ENDSWITH[c] '.png' OR label ENDSWITH[c] '.heic' OR label ENDSWITH[c] '.heif'"
        ))
        let names = imageLabels.allElementsBoundByIndex.map { $0.label }
        try XCTSkipUnless(names.count >= 2, "At least two test images are required")
        let firstName = names[0]
        let firstImage = table.staticTexts[firstName]
        for _ in 0..<12 {
            if firstImage.isHittable { break }
            table.swipeUp()
        }
        XCTAssertTrue(firstImage.isHittable)
        firstImage.tap()
        let thumbnails = app.collectionViews["gallery_thumbnails"]
        XCTAssertTrue(thumbnails.waitForExistence(timeout: 20))
        XCTAssertTrue(app.navigationBars.staticTexts[firstName].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(thumbnails.cells.count, 1)
        // Collection queries expose the currently materialized thumbnails.
        // Choose a different visible image, without assuming the final file is loaded.
        thumbnails.cells.element(boundBy: thumbnails.cells.count - 1).tap()
        let title = app.navigationBars.staticTexts.firstMatch
        let updated = expectation(for: NSPredicate(format: "label != %@ AND label != ''", firstName), evaluatedWith: title)
        wait(for: [updated], timeout: 10)
        let updatedName = title.label
        attachScreenshot("gallery-updated-title")
        app.buttons["navigation_back_button"].tap()
        XCTAssertTrue(app.buttons["directory_more_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(table.staticTexts[updatedName].exists,
                      "The updated title must identify a file in this library")
    }

    func testGalleryFitsPhotoAndPreservesZoomAcrossChromeChanges() throws {
        let table = try openAdaptationLibrary()
        let file = table.staticTexts.matching(NSPredicate(
            format: "label ENDSWITH[c] '.png' OR label ENDSWITH[c] '.jpg' OR label ENDSWITH[c] '.jpeg'"
        )).firstMatch
        XCTAssertTrue(file.exists)
        scrollToFile(file, in: table)
        let fileName = file.label
        file.tap()
        let thumbnails = app.collectionViews["gallery_thumbnails"]
        XCTAssertTrue(thumbnails.waitForExistence(timeout: 20))
        let viewport = try XCTUnwrap(app.scrollViews.matching(identifier: "gallery_photo_viewport")
            .allElementsBoundByIndex.first(where: { $0.frame.contains(CGPoint(x: thumbnails.frame.midX,
                                                                            y: thumbnails.frame.minY - 10)) }))
        let photo = viewport.images["gallery_photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 20))
        // The image view exists at its initial full-window size while the file
        // is still downloading. Its label is assigned when the image is fitted.
        let loaded = expectation(for: NSPredicate { _, _ in
            photo.label == fileName && photo.frame.width > 1 && photo.isHittable
        },
                                 evaluatedWith: photo)
        wait(for: [loaded], timeout: 20)

        func assertFitted() {
            let image = photo.frame, area = viewport.frame
            XCTAssertGreaterThanOrEqual(image.minX, area.minX - 1)
            XCTAssertGreaterThanOrEqual(image.minY, area.minY - 1)
            XCTAssertLessThanOrEqual(image.maxX, area.maxX + 1)
            XCTAssertLessThanOrEqual(image.maxY, area.maxY + 1)
            XCTAssertEqual(image.midX, area.midX, accuracy: 1)
            XCTAssertEqual(image.midY, area.midY, accuracy: 1)
        }
        func tapPhoto() {
            viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        func waitForChrome(_ visible: Bool) {
            let settled = expectation(for: NSPredicate { _, _ in
                thumbnails.isHittable == visible && photo.isHittable
            }, evaluatedWith: thumbnails)
            wait(for: [settled], timeout: 8)
        }
        func focalPoint() -> CGPoint {
            let image = photo.frame, area = viewport.frame
            return CGPoint(x: (area.midX - image.minX) / image.width,
                           y: (area.midY - image.minY) / image.height)
        }

        let normalArea = viewport.frame
        let fittedImageWidth = photo.frame.width
        XCTAssertEqual(normalArea.minX, thumbnails.frame.minX, accuracy: 1)
        XCTAssertEqual(normalArea.maxX, thumbnails.frame.maxX, accuracy: 1)
        XCTAssertLessThanOrEqual(normalArea.maxY, thumbnails.frame.minY + 1)
        let title = app.navigationBars.staticTexts.firstMatch
        if title.exists { XCTAssertGreaterThanOrEqual(normalArea.minY, title.frame.maxY - 1) }
        assertFitted()
        attachScreenshot("gallery-fitted-normal")

        tapPhoto()
        waitForChrome(false)
        let immersiveArea = viewport.frame
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(immersiveArea.minX, window.minX, accuracy: 1)
        XCTAssertEqual(immersiveArea.maxX, window.maxX, accuracy: 1)
        XCTAssertGreaterThan(immersiveArea.height, normalArea.height)
        assertFitted()
        attachScreenshot("gallery-fitted-immersive")
        tapPhoto()
        waitForChrome(true)
        assertFitted()

        // Zoom, pan away from center, then show/hide controls. The displayed
        // photo size and image point at the viewport center must survive both.
        viewport.pinch(withScale: 3, velocity: 2)
        waitForChrome(false)
        let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6))
        let end = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
        let zoomedSize = photo.frame.size
        let focus = focalPoint()
        XCTAssertGreaterThan(zoomedSize.width, fittedImageWidth * 1.5)
        for visible in [true, false, true] {
            tapPhoto()
            waitForChrome(visible)
            XCTAssertEqual(photo.frame.width, zoomedSize.width, accuracy: 2)
            XCTAssertEqual(photo.frame.height, zoomedSize.height, accuracy: 2)
            XCTAssertEqual(focalPoint().x, focus.x, accuracy: 0.015)
            XCTAssertEqual(focalPoint().y, focus.y, accuracy: 0.015)
        }
        attachScreenshot("gallery-zoom-preserved")
        viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
        waitForChrome(true)
        assertFitted()
    }

    func testGalleryPropertiesLayout() throws {
        let table = try openAdaptationLibrary()
        let file = table.staticTexts.matching(NSPredicate(format: "label ENDSWITH[c] '.png'")).firstMatch
        XCTAssertTrue(file.exists)
        scrollToFile(file, in: table)
        file.tap()
        let button = app.buttons["gallery_info_button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        let thumbnails = app.collectionViews["gallery_thumbnails"]
        let toolbar = app.otherElements["gallery_toolbar"]

        func verifyProperties() throws -> XCUIElement {
            let panels = app.otherElements.matching(identifier: "gallery_info_panel")
            XCTAssertTrue(panels.firstMatch.waitForExistence(timeout: 10))
            let panel = try XCTUnwrap(panels.allElementsBoundByIndex.first(where: {
                $0.isHittable && $0.frame.minX <= toolbar.frame.midX && $0.frame.maxX >= toolbar.frame.midX
            }),
                                      "No visible properties panel")
            let content = panel.scrollViews["gallery_info_content"]
            let label = content.staticTexts.matching(identifier: "gallery_property_label").firstMatch
            XCTAssertTrue(label.waitForExistence(timeout: 30), "Metadata must load")
            print("DUO_PROPERTIES panel=\(panel.frame) strip=\(thumbnails.frame) toolbar=\(toolbar.frame)")
            XCTAssertGreaterThanOrEqual(panel.frame.minY, thumbnails.frame.maxY - 1)
            XCTAssertLessThanOrEqual(panel.frame.maxY, toolbar.frame.minY + 1)
            XCTAssertGreaterThanOrEqual(panel.frame.minX, thumbnails.frame.minX - 1)
            XCTAssertLessThanOrEqual(panel.frame.maxX, thumbnails.frame.maxX + 1)
            XCTAssertLessThanOrEqual(content.frame.width, 641)
            XCTAssertTrue(label.isHittable, "The first property must not be covered by thumbnails")
            XCTAssertGreaterThanOrEqual(label.frame.minY, content.frame.minY)
            XCTAssertTrue(button.isHittable)
            return content
        }

        button.tap()
        let content = try verifyProperties()
        attachScreenshot("gallery-properties-layout")
        content.swipeUp()
        content.swipeDown()
        // Switching photos must preserve the panel geometry and load the new metadata.
        XCTAssertGreaterThan(thumbnails.cells.count, 1)
        thumbnails.cells.element(boundBy: 0).tap()
        _ = try verifyProperties()
        attachScreenshot("gallery-properties-after-photo-change")
        button.tap()
        XCTAssertTrue(app.buttons["navigation_back_button"].waitForExistence(timeout: 10))
        button.tap()
        _ = try verifyProperties()
        button.tap()
        app.buttons["navigation_back_button"].tap()
        XCTAssertTrue(app.buttons["directory_more_button"].waitForExistence(timeout: 10))
    }

    func testPDFPreviewReadOnly() throws {
        let table = try openAdaptationLibrary()
        let file = table.staticTexts.matching(NSPredicate(format: "label ENDSWITH[c] '.pdf'")).firstMatch
        XCTAssertTrue(file.exists, "A PDF fixture is required")
        let name = file.label
        scrollToFile(file, in: table)
        file.tap()
        let preview = app.otherElements["seafile_quicklook"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10))
        print("DUO_PREVIEW_READY \(name)")
        attachScreenshot("preview-pdf")
        let close = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(app.buttons["directory_more_button"].waitForExistence(timeout: 10))
    }

    func testTextPreviewReadOnly() throws {
        try openTestFile(named: "Bb.txt")
        XCTAssertTrue(app.navigationBars["Bb.txt"].waitForExistence(timeout: 30))
        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertFalse((text.value as? String ?? "").isEmpty)
        print("DUO_TEXT_READY")
        attachScreenshot("preview-text")
        let close = app.buttons["navigation_close_button"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(app.buttons["directory_more_button"].waitForExistence(timeout: 10))
    }

    private func openTestFile(named name: String) throws {
        let table = try openAdaptationLibrary()
        let file = table.staticTexts[name]
        XCTAssertTrue(file.waitForExistence(timeout: 10), "Missing fixture: \(name)")
        scrollToFile(file, in: table)
        file.tap()
    }

    private func scrollToFile(_ file: XCUIElement, in table: XCUIElement) {
        for _ in 0..<20 {
            if file.isHittable { break }
            table.swipeUp()
        }
        XCTAssertTrue(file.isHittable)
    }

    func testSdocSoftwareKeyboardAvoidance() throws {
        try openTestFile(named: "照片浏览实现文档_草稿 (1).sdoc")
        let edit = app.buttons["sdoc_edit_button"]
        XCTAssertTrue(edit.waitForExistence(timeout: 30))
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: edit)
        wait(for: [ready], timeout: 30)
        edit.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        XCTAssertTrue(web.staticTexts.firstMatch.exists)
        let firstText = web.staticTexts[web.staticTexts.firstMatch.label].firstMatch
        let originalTextFrame = firstText.frame
        web.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.3)).tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 60), "Enable the simulator software keyboard")
        print("DUO_KEYBOARD_READY")
        XCTAssertGreaterThan(keyboard.frame.height, 150, "A full software keyboard is required")
        let toolbar = app.otherElements["sdoc_editor_toolbar"]
        XCTAssertTrue(toolbar.exists)
        XCTAssertLessThanOrEqual(toolbar.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertGreaterThan(toolbar.frame.height, 0)
        XCTAssertGreaterThanOrEqual(toolbar.frame.minX, web.frame.minX - 1)
        XCTAssertLessThanOrEqual(toolbar.frame.maxX, web.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(firstText.frame.minX, originalTextFrame.minX - 1,
                                    "Keyboard focus must not shift the start of the document offscreen")
        XCTAssertEqual(firstText.frame.width, originalTextFrame.width, accuracy: 2,
                       "Keyboard focus must not automatically zoom the document")
        attachScreenshot("sdoc-software-keyboard")
        let raisedBottom = toolbar.frame.maxY
        let hideKeyboard = app.buttons["sdoc_dismiss_keyboard_button"]
        XCTAssertTrue(hideKeyboard.isHittable)
        hideKeyboard.tap()
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: keyboard)
        wait(for: [hidden], timeout: 10)
        XCTAssertGreaterThan(toolbar.frame.maxY, raisedBottom + 100,
                             "The toolbar must return to the bottom after keyboard dismissal")
        let unzoomedWidth = firstText.frame.width
        web.pinch(withScale: 1.3, velocity: 1)
        XCTAssertGreaterThan(firstText.frame.width, unzoomedWidth * 1.05,
                             "Users must still be able to pinch to enlarge the document")
        app.buttons["navigation_back_button"].tap()
        XCTAssertTrue(app.buttons["directory_more_button"].waitForExistence(timeout: 10))
    }

    private func openAdaptationLibrary() throws -> XCUIElement {
        let root = try waitForLibraryTable()
        // The signed-in simulator's agreed test fixture; override in the scheme
        // environment when running against another test account.
        let libraryName = ProcessInfo.processInfo.environment["DUO_TEST_LIBRARY"] ?? "999"
        let library = root.cells.containing(.staticText, identifier: libraryName).firstMatch
        try XCTSkipUnless(library.exists, "Test library '\(libraryName)' is required")
        library.tap()
        let viewMode = app.buttons["directory_view_mode_button"]
        XCTAssertTrue(viewMode.waitForExistence(timeout: 10))
        if viewMode.label.contains("列表") || viewMode.label.lowercased().contains("list") {
            viewMode.tap()
        }
        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        return table
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
        let more = app.buttons["directory_more_button"]
        let hasLibrary = more.waitForExistence(timeout: 20)
        XCTAssertEqual(app.state, .runningForeground, "The app must remain running during setup")
        let addAccount = app.buttons.matching(
            NSPredicate(format: "label == 'Add Account' OR label == '添加账户' OR label == '添加帐号' OR label == '添加账号'")
        ).firstMatch
        try XCTSkipIf(
            !hasLibrary && addAccount.exists,
            "The account screen is open; sign in on the booted simulator first."
        )
        XCTAssertTrue(hasLibrary, "Expected the library navigation controls")
        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 10), "Expected the library list")
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
        // Duo can keep the default display inactive while the app uses the other one.
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
