import XCTest

final class ProfileEditUITests: XCTestCase {

    private var app: XCUIApplication!

    private let repoName = ProcessInfo.processInfo.environment["UI_TEST_REPO"] ?? "8888"
    private let folderName = ProcessInfo.processInfo.environment["UI_TEST_FOLDER"] ?? "Camera Uploads"

    override func setUpWithError() throws {
        continueAfterFailure = false
        relaunch()
    }

    private func relaunch(extraArgs: [String] = []) {
        if let running = app {
            running.terminate()
        }
        app = XCUIApplication()
        app.launchArguments = ["-UI_TESTING", "1"] + extraArgs
        app.launch()
    }

    // MARK: - Navigation

    func testA01_SingleFileOpensProperties() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
    }

    func testA02_FolderPropertiesDisabled() throws {
        loginIfNeeded()
        openRepoOnly()
        selectFolder()
        let propertiesButton = propertiesToolbarElement()
        XCTAssertTrue(propertiesButton.waitForExistence(timeout: 8))
        propertiesButton.tap()
        XCTAssertFalse(
            app.buttons["profile_edit_button"].waitForExistence(timeout: 3),
            "Properties sheet should not open for folders"
        )
    }

    func testA03_MultiSelectPropertiesDisabled() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectMultipleFiles(count: 2)
        let propertiesButton = propertiesToolbarElement()
        XCTAssertTrue(propertiesButton.waitForExistence(timeout: 8))
        propertiesButton.tap()
        XCTAssertFalse(
            app.buttons["profile_edit_button"].waitForExistence(timeout: 3),
            "Properties sheet should not open for multi-select"
        )
    }

    func testA04_RepoRootPropertiesDisabled() throws {
        loginIfNeeded()
        let repo = app.tables.staticTexts[repoName].firstMatch
        XCTAssertTrue(repo.waitForExistence(timeout: 10))
        repo.press(forDuration: 0.9)
        let propertiesButton = propertiesToolbarElement()
        if propertiesButton.waitForExistence(timeout: 5) {
            propertiesButton.tap()
            XCTAssertFalse(
                app.buttons["profile_edit_button"].waitForExistence(timeout: 3),
                "Properties sheet should not open at repo root selection"
            )
        }
    }

    func testB01_SheetTitleAndLayout() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        XCTAssertTrue(app.scrollViews.firstMatch.exists, "Sheet content should be scrollable")
    }

    func testB02_MetadataShowsEditButton() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        XCTAssertTrue(app.buttons["profile_edit_button"].exists)
    }

    func testB06_ClosePropertiesSheet() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        let editButton = app.buttons["profile_edit_button"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.swipeDown(velocity: .fast)
        if editButton.waitForExistence(timeout: 2) {
            app.swipeDown(velocity: .fast)
        }
        XCTAssertFalse(editButton.waitForExistence(timeout: 5))
    }

    func testC01_EnterEditPage() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
    }

    func testC02_CancelEditDiscardsChanges() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        let descriptionField = scrollToElement(id: "editor_longtext__description", asButton: true)
        descriptionField?.tap()
        let textView = app.textViews["longtext_editor_textview"]
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.typeText("SHOULD_NOT_SAVE")
        app.buttons["profile_longtext_done_button"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(app.buttons["profile_save_button"].waitForExistence(timeout: 3))
    }

    func testC03_SaveWithNoChanges() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        app.buttons["profile_save_button"].tap()
        // SVProgressHUD may not always surface to accessibility; staying on edit page is the key signal.
        XCTAssertTrue(app.buttons["profile_save_button"].waitForExistence(timeout: 5), "Should stay on edit page")
        let noChanges = app.staticTexts.element(
            matching: NSPredicate(format: "label CONTAINS[c] 'change' OR label CONTAINS '无' OR label CONTAINS '更改'")
        )
        _ = noChanges.waitForExistence(timeout: 3)
    }

    func testC04_SaveSuccess() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        exerciseDescriptionEditor()
        saveProfile()
        verifyReturnedToFileListAfterSave()
    }

    func testD01_LongTextInputAndDone() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        exerciseDescriptionEditor()
    }

    func testD02_LongTextKeyboardRefocus() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        exerciseDescriptionEditor()
    }

    func testA05_ProfileLoadFailure() throws {
        relaunch(extraArgs: ["-UI_TEST_FAIL_PROFILE_LOAD"])
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        propertiesToolbarElement().tap()
        let errorHUD = app.staticTexts.element(
            matching: NSPredicate(format: "label CONTAINS 'Failed' OR label CONTAINS '失败' OR label CONTAINS 'load'")
        )
        XCTAssertTrue(errorHUD.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["profile_edit_button"].waitForExistence(timeout: 2))
    }

    func testA06_NoProfileData() throws {
        relaunch(extraArgs: ["-UI_TEST_EMPTY_PROFILE"])
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        propertiesToolbarElement().tap()
        XCTAssertFalse(app.buttons["profile_edit_button"].waitForExistence(timeout: 8))
    }

    func testB03_MetadataDisabledHidesEdit() throws {
        relaunch(extraArgs: ["-UI_TEST_METADATA_DISABLED"])
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet(requireEditButton: false)
        XCTAssertFalse(app.buttons["profile_edit_button"].exists)
    }

    func testB04_SheetShowsMultipleFields() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        XCTAssertGreaterThan(app.staticTexts.count, 3, "Sheet should list multiple field labels/values")
    }

    func testB05_EmptyPlaceholderNotChip() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        // Regression: empty tags should not render a chip literally labeled "empty"
        let bogusChip = app.staticTexts["empty"]
        XCTAssertFalse(bogusChip.exists, "Should not show a chip titled 'empty'")
    }

    func testB07_SdocProfileEntry() throws {
        loginIfNeeded()
        openRepoOnly()
        let sdocCell = app.tables.cells.matching(
            NSPredicate(format: "label MATCHES[c] '.*\\.sdoc$'")
        ).firstMatch
        guard sdocCell.waitForExistence(timeout: 5) else {
            throw XCTSkip("No .sdoc file in test repo root")
        }
        sdocCell.tap()
        let profileBtn = app.buttons["sdoc_profile_toolbar_button"]
        XCTAssertTrue(profileBtn.waitForExistence(timeout: 15))
        profileBtn.tap()
        XCTAssertTrue(app.buttons["profile_edit_button"].waitForExistence(timeout: 10))
    }

    func testC05_SaveFailure() throws {
        relaunch(extraArgs: ["-UI_TEST_FAIL_PROFILE_SAVE"])
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        exerciseDescriptionEditor()
        app.buttons["profile_save_button"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile_save_button"].exists)
    }

    func testD03_LongTextCancel() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        scrollToElement(id: "editor_longtext__description", asButton: true)?.tap()
        let textView = app.textViews["longtext_editor_textview"]
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.typeText("CANCEL_ME")
        app.buttons["profile_longtext_cancel_button"].tap()
        XCTAssertTrue(app.buttons["profile_save_button"].waitForExistence(timeout: 5))
    }

    func testD08_TagRemove() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        exerciseTagsIfPresent()
        let remove = scrollToElement(id: "tag_chip_remove_button", asButton: true)
        guard remove != nil else {
            throw XCTSkip("No removable tag chip in test file")
        }
        remove?.tap()
    }

    func testD09_CollaboratorSelect() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        let field = scrollToElement(id: "editor_collaborator__collaborators", asButton: false)
            ?? scrollToElement(id: "editor_collaborator__reviewer", asButton: false)
            ?? scrollToElement(id: "editor_collaborator__owner", asButton: false)
        guard let field else { throw XCTSkip("No collaborator field in test metadata") }
        field.tap()
        XCTAssertTrue(app.tables.firstMatch.waitForExistence(timeout: 5))
        app.buttons["option_selector_cancel_button"].tap()
        XCTAssertTrue(app.buttons["profile_save_button"].waitForExistence(timeout: 5))
    }

    func testD10_DatePicker() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        guard let dateField = scrollToElement(id: "editor_date__expire_time", asButton: false) else {
            throw XCTSkip("No expire_time date field")
        }
        dateField.tap()
        XCTAssertTrue(app.buttons["date_selector_done_button"].waitForExistence(timeout: 5))
        app.buttons["date_selector_done_button"].tap()
        XCTAssertTrue(app.buttons["profile_save_button"].waitForExistence(timeout: 5))
    }

    func testD11_InlineTextField() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        let textField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'editor_text_'")
        ).firstMatch
        guard textField.waitForExistence(timeout: 3) else {
            throw XCTSkip("No inline text field in metadata")
        }
        textField.tap()
        textField.typeText("X")
    }

    func testD12_MultiSelectOrCheckbox() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        let multi = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'editor_multiselect_'")
        ).firstMatch
        if multi.waitForExistence(timeout: 3) {
            multi.tap()
            XCTAssertTrue(app.tables.firstMatch.waitForExistence(timeout: 5))
            app.buttons["option_selector_cancel_button"].tap()
            return
        }
        let checkbox = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH 'editor_checkbox_'")
        ).firstMatch
        guard checkbox.waitForExistence(timeout: 3) else {
            throw XCTSkip("No multi-select or checkbox field")
        }
        checkbox.tap()
    }

    func testE01_TagSelectorCancel() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        guard scrollToElement(id: "editor_tags_add_button", asButton: true) != nil else {
            throw XCTSkip("No tags field")
        }
        app.buttons["editor_tags_add_button"].tap()
        XCTAssertTrue(app.buttons["tag_selector_cancel_button"].waitForExistence(timeout: 5))
        app.buttons["tag_selector_cancel_button"].tap()
        XCTAssertTrue(app.buttons["profile_save_button"].waitForExistence(timeout: 5))
    }

    func testE02_OptionSelectorCancel() throws {
        try testD09_CollaboratorSelect()
    }

    func testE03_DatePickerCancel() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        guard let dateField = scrollToElement(id: "editor_date__expire_time", asButton: false) else {
            throw XCTSkip("No date field")
        }
        dateField.tap()
        app.buttons["date_selector_cancel_button"].tap()
        XCTAssertTrue(app.buttons["profile_save_button"].waitForExistence(timeout: 5))
    }

    func testE04_EditPageDismissKeyboard() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        let textField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'editor_text_'")
        ).firstMatch
        guard textField.waitForExistence(timeout: 3) else {
            throw XCTSkip("No inline text field")
        }
        textField.tap()
        _ = app.keyboards.element.waitForExistence(timeout: 3)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(waitUntilKeyboardHidden(timeout: 3))
    }

    /// Full property-edit regression: sheet → edit page → description / status / rate / tags → save.
    func testPropertyEditFlow() throws {
        loginIfNeeded()
        openRepoAndFolder()
        selectFirstFile()
        openPropertiesSheet()
        openEditPage()
        exerciseDescriptionEditor()
        exerciseFileStatusIfPresent()
        exerciseRateIfPresent()
        exerciseTagsIfPresent()
        saveProfile()
        verifyReturnedToFileListAfterSave()
    }

    // MARK: - Navigation

    private func loginIfNeeded() {
        let welcome = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Welcome' OR label CONTAINS '欢迎使用'")
        ).firstMatch
        guard welcome.waitForExistence(timeout: 3) else { return }

        let account = app.tables.cells.firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5), "Account cell should exist on login screen")
        account.tap()

        let libraryTab = app.tabBars.buttons.element(
            matching: NSPredicate(format: "label CONTAINS 'Library' OR label CONTAINS '资料库'")
        )
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 15), "Should reach library tab after login")
    }

    private func openRepoAndFolder() {
        openRepoOnly()

        let folderCell = app.tables.cells.containing(.staticText, identifier: folderName).firstMatch
        if !folderCell.waitForExistence(timeout: 5) {
            let gridCell = app.collectionViews.cells.containing(.staticText, identifier: folderName).firstMatch
            XCTAssertTrue(gridCell.waitForExistence(timeout: 5), "Folder \(folderName) should be visible")
            gridCell.tap()
        } else {
            folderCell.tap()
        }

        let firstRow = app.tables.cells.firstMatch
        if !firstRow.waitForExistence(timeout: 5) {
            XCTAssertTrue(app.collectionViews.cells.firstMatch.waitForExistence(timeout: 5), "File list should load")
        }
    }

    private func openRepoOnly() {
        let repo = app.tables.staticTexts[repoName].firstMatch
        XCTAssertTrue(repo.waitForExistence(timeout: 10), "Repo \(repoName) should be visible")
        repo.tap()
        XCTAssertTrue(app.tables.cells.firstMatch.waitForExistence(timeout: 8), "Repo folder list should load")
    }

    private func propertiesToolbarElement() -> XCUIElement {
        let button = app.buttons["profile_properties_toolbar_button"]
        if button.exists { return button }
        return app.otherElements["profile_properties_toolbar_button"]
    }

    private var fileExtensionLabelPredicate: NSPredicate {
        NSPredicate(format: "label MATCHES[c] '.*\\.(png|jpg|jpeg|heic|pdf|txt|mp4)$'")
    }

    private func selectFirstFile() {
        let tableFile = app.tables.cells.matching(fileExtensionLabelPredicate).firstMatch
        let target: XCUIElement
        if tableFile.waitForExistence(timeout: 5) {
            target = tableFile
        } else {
            let gridFile = app.collectionViews.cells.matching(fileExtensionLabelPredicate).firstMatch
            if gridFile.waitForExistence(timeout: 5) {
                target = gridFile
            } else {
                let tableFallback = app.tables.cells.element(boundBy: 1)
                target = tableFallback.waitForExistence(timeout: 2)
                    ? tableFallback
                    : app.collectionViews.cells.element(boundBy: 1)
            }
        }
        XCTAssertTrue(target.waitForExistence(timeout: 5), "A file row should exist")
        target.press(forDuration: 0.9)

        let propertiesButton = propertiesToolbarElement()
        XCTAssertTrue(
            propertiesButton.waitForExistence(timeout: 8),
            "Properties toolbar button should appear for a single file"
        )
        XCTAssertTrue(propertiesButton.isEnabled, "Properties button should be enabled")
    }

    private func selectFolder() {
        let folderCell = app.tables.cells.containing(.staticText, identifier: folderName).firstMatch
        XCTAssertTrue(folderCell.waitForExistence(timeout: 8), "Folder should exist")
        folderCell.press(forDuration: 0.9)
        XCTAssertTrue(propertiesToolbarElement().waitForExistence(timeout: 8))
    }

    private func selectMultipleFiles(count: Int) {
        let tableFiles = app.tables.cells.matching(fileExtensionLabelPredicate)
        let gridFiles = app.collectionViews.cells.matching(fileExtensionLabelPredicate)
        if tableFiles.count >= count {
            tableFiles.element(boundBy: 0).press(forDuration: 0.9)
            tableFiles.element(boundBy: 1).tap()
        } else if gridFiles.count >= count {
            gridFiles.element(boundBy: 0).press(forDuration: 0.9)
            gridFiles.element(boundBy: 1).tap()
        } else {
            let tableAll = app.tables.cells
            if tableAll.count >= count {
                tableAll.element(boundBy: 0).press(forDuration: 0.9)
                tableAll.element(boundBy: 1).tap()
            } else {
                let gridAll = app.collectionViews.cells
                XCTAssertGreaterThanOrEqual(gridAll.count, count, "Need at least \(count) list rows")
                gridAll.element(boundBy: 0).press(forDuration: 0.9)
                gridAll.element(boundBy: 1).tap()
            }
        }
        XCTAssertTrue(propertiesToolbarElement().waitForExistence(timeout: 8))
    }

    private func openPropertiesSheet(requireEditButton: Bool = true) {
        propertiesToolbarElement().tap()

        if requireEditButton {
            let editButton = app.buttons["profile_edit_button"]
            XCTAssertTrue(editButton.waitForExistence(timeout: 8), "Profile sheet should show Edit button")
        } else {
            _ = app.staticTexts.element(
                matching: NSPredicate(format: "label CONTAINS 'Properties' OR label CONTAINS '属性'")
            ).waitForExistence(timeout: 8)
        }

        let propertiesTitle = app.staticTexts.element(
            matching: NSPredicate(format: "label CONTAINS 'Properties' OR label CONTAINS '属性'")
        )
        XCTAssertTrue(propertiesTitle.exists, "Profile sheet title should be visible")
    }

    private func openEditPage() {
        app.buttons["profile_edit_button"].tap()

        let saveButton = app.buttons["profile_save_button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 8), "Edit page Save button should appear")

        let editNav = app.navigationBars.element(
            matching: NSPredicate(format: "identifier CONTAINS 'Edit' OR identifier CONTAINS '编辑'")
        )
        XCTAssertTrue(editNav.waitForExistence(timeout: 3), "Edit navigation bar should be visible")
    }

    // MARK: - Field editors

    private func exerciseDescriptionEditor() {
        let descriptionField = scrollToElement(id: "editor_longtext__description", asButton: true)
        XCTAssertNotNil(descriptionField, "Description field should be visible")
        descriptionField?.tap()

        let textView = app.textViews["longtext_editor_textview"]
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "Long text editor should open")

        XCTAssertTrue(
            app.keyboards.element.waitForExistence(timeout: 5),
            "Keyboard should appear when long text editor opens"
        )

        let marker = "UI_TEST_\(Int(Date().timeIntervalSince1970))"
        textView.typeText(marker)

        textView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(
            waitUntilKeyboardHidden(timeout: 3),
            "Keyboard should dismiss after tapping blank area in text view"
        )

        textView.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
        XCTAssertTrue(
            app.keyboards.element.waitForExistence(timeout: 3),
            "Keyboard should appear when text view is refocused"
        )

        app.buttons["profile_longtext_done_button"].tap()
        XCTAssertTrue(app.buttons["profile_save_button"].waitForExistence(timeout: 5))
    }

    private func exerciseFileStatusIfPresent() {
        // Prefer stable id; fall back to localized status label.
        let statusOption = scrollToElement(
            matching: NSPredicate(format: "identifier BEGINSWITH 'editor_select__status_'")
        ) ?? scrollToStaticText(matching: "In progress|进行中|Done|已完成")
        guard let statusOption else { return }

        statusOption.tap()
        // Toggle off by tapping again (Android-aligned behaviour)
        statusOption.tap()
    }

    private func exerciseRateIfPresent() {
        guard let star = scrollToElement(id: "editor_rate__rate_3", asButton: true) else { return }
        star.tap()
        // Tap same star again to clear rating
        star.tap()
        star.tap()
    }

    private func exerciseTagsIfPresent() {
        let addButton = scrollToElement(id: "editor_tags_add_button", asButton: true)
        let tagsArea = scrollToElement(id: "editor_tags__tags", asButton: false)
        guard addButton != nil || tagsArea != nil else { return }

        if let addButton {
            addButton.tap()
        } else {
            tagsArea?.tap()
        }

        let tagTable = app.tables.firstMatch
        XCTAssertTrue(tagTable.waitForExistence(timeout: 5), "Tag selector should appear")

        let firstTag = tagTable.cells.firstMatch
        if firstTag.waitForExistence(timeout: 3) {
            firstTag.tap()
        }

        let done = app.buttons["tag_selector_done_button"]
        if done.waitForExistence(timeout: 2) {
            done.tap()
        } else {
            app.buttons.element(
                matching: NSPredicate(format: "label CONTAINS 'Done' OR label CONTAINS '完成'")
            ).tap()
        }

        XCTAssertTrue(app.buttons["profile_save_button"].waitForExistence(timeout: 5))
    }

    private func saveProfile() {
        if let save = scrollToElement(id: "profile_save_button", asButton: true) {
            save.tap()
        } else {
            app.buttons["profile_save_button"].tap()
        }

        let successHUD = app.staticTexts.element(
            matching: NSPredicate(format: "label CONTAINS 'success' OR label CONTAINS '成功' OR label CONTAINS 'Saved' OR label CONTAINS '保存'")
        )
        _ = successHUD.waitForExistence(timeout: 10)

        // Editor dismisses 1s after success HUD (see onSaveTapped dispatch_after).
        let stillOnEditPage = app.buttons["profile_save_button"].waitForExistence(timeout: 5)
        XCTAssertFalse(stillOnEditPage, "Edit page should dismiss after save")
    }

    private func verifyReturnedToFileListAfterSave() {
        let fileTable = app.tables.firstMatch
        let fileGrid = app.collectionViews.firstMatch
        let listVisible = fileTable.waitForExistence(timeout: 10) || fileGrid.waitForExistence(timeout: 3)
        XCTAssertTrue(listVisible, "Should return to file list after save")

        XCTAssertFalse(app.buttons["profile_save_button"].exists, "Edit page should stay closed")
        XCTAssertFalse(app.buttons["profile_edit_button"].exists, "Properties sheet should stay closed")
    }

    // MARK: - Helpers

    @discardableResult
    private func scrollToElement(id: String, asButton: Bool = false, maxSwipes: Int = 6) -> XCUIElement? {
        var swipes = 0
        while swipes <= maxSwipes {
            let candidates: [XCUIElement] = asButton
                ? [app.buttons[id]]
                : [app.buttons[id], app.staticTexts[id], app.otherElements[id]]
            if let found = candidates.first(where: { $0.exists }) {
                return found
            }
            if swipes == maxSwipes { break }
            app.swipeUp()
            swipes += 1
        }
        return nil
    }

    @discardableResult
    private func scrollToElement(matching predicate: NSPredicate, maxSwipes: Int = 6) -> XCUIElement? {
        var swipes = 0
        while swipes <= maxSwipes {
            let element = app.otherElements.matching(predicate).firstMatch
            if element.exists { return element }
            if swipes == maxSwipes { break }
            app.swipeUp()
            swipes += 1
        }
        return nil
    }

    @discardableResult
    private func scrollToStaticText(matching pattern: String, maxSwipes: Int = 6) -> XCUIElement? {
        let predicate = NSPredicate(format: "label MATCHES[c] %@", pattern)
        var swipes = 0
        while swipes <= maxSwipes {
            let element = app.staticTexts.matching(predicate).firstMatch
            if element.exists { return element }
            if swipes == maxSwipes { break }
            app.swipeUp()
            swipes += 1
        }
        return nil
    }

    private func waitUntilKeyboardHidden(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.keyboards.count == 0 { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return app.keyboards.count == 0
    }
}

// MARK: - Issue #547: Files app folder favorites

final class FilesAppFavoritesUITests: XCTestCase {

    private var filesApp: XCUIApplication!
    private let repoName = ProcessInfo.processInfo.environment["UI_TEST_REPO"] ?? "8888"
    private let folderName = ProcessInfo.processInfo.environment["UI_TEST_FOLDER"] ?? "Camera Uploads"

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Prime the file provider extension with account data if Seafile is available.
        let seafile = XCUIApplication(bundleIdentifier: "com.seafile.seafilePro")
        seafile.launchArguments = ["-UI_TESTING", "1"]
        seafile.launch()
        _ = seafile.tabBars.buttons.element(
            matching: NSPredicate(format: "label CONTAINS 'Librar' OR label CONTAINS '资料库'")
        ).waitForExistence(timeout: 15)
        sleep(2)
        seafile.terminate()

        filesApp = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        // Force English so label-based queries ("Browse", "Favorite", ...) work on
        // devices whose system language is not English.
        filesApp.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // Route the Files app's os_log output to stderr so client-side FileProvider errors
        // (bookmark resolution, favorite-rank failures) show up in the test logs.
        filesApp.launchEnvironment["OS_ACTIVITY_DT_MODE"] = "YES"
        filesApp.launch()
    }

    /// Read-only diagnostic: relaunches Files twice and captures the Browse root
    /// (Favorites section) each time. Mutates nothing; used to observe whether
    /// existing favorites survive a relaunch on a device with legacy state.
    func testZZ_ReadOnly_DumpFavoritesAfterRelaunch() throws {
        attachSidebarSnapshot(label: "1-initial")

        filesApp.terminate()
        sleep(1)
        filesApp.launch()
        sleep(3)
        attachSidebarSnapshot(label: "2-after-relaunch-1")

        filesApp.terminate()
        sleep(1)
        filesApp.launch()
        sleep(3)
        attachSidebarSnapshot(label: "3-after-relaunch-2")
    }

    private func attachSidebarSnapshot(label: String) {
        let browse = filesApp.tabBars.buttons["Browse"]
        if browse.waitForExistence(timeout: 5) {
            browse.tap()
            sleep(1)
            // A second tap pops back to the Browse root if a location was open.
            browse.tap()
        }
        sleep(2)
        let shot = XCTAttachment(screenshot: filesApp.screenshot())
        shot.name = "\(label)-top"
        shot.lifetime = .keepAlways
        add(shot)

        filesApp.swipeUp()
        sleep(1)
        let shot2 = XCTAttachment(screenshot: filesApp.screenshot())
        shot2.name = "\(label)-scrolled"
        shot2.lifetime = .keepAlways
        add(shot2)

        let labels = filesApp.cells.allElementsBoundByIndex.prefix(40).map { $0.label }
        let att = XCTAttachment(string: labels.joined(separator: "\n"))
        att.name = "\(label)-cells"
        att.lifetime = .keepAlways
        add(att)
    }

    func testIssue547_FolderFavoritePersistsAfterRelaunch() throws {
        navigateToFolderInSeafileProvider()

        removeFavoriteIfPresent(named: folderName)

        navigateToFolderInSeafileProvider()

        var folderCell = filesApp.cells.containing(.staticText, identifier: folderName).firstMatch
        if !folderCell.waitForExistence(timeout: 8) {
            folderCell = filesApp.staticTexts[folderName].firstMatch
        }
        XCTAssertTrue(folderCell.waitForExistence(timeout: 10), "Folder \(folderName) should be visible in Files app")
        folderCell.tap()
        XCTAssertTrue(waitForFolderContents(), "Folder \(folderName) should list items when opened normally")

        let backButton = filesApp.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        }

        folderCell = filesApp.cells.containing(.staticText, identifier: folderName).firstMatch
        if !folderCell.waitForExistence(timeout: 5) {
            folderCell = filesApp.staticTexts[folderName].firstMatch
        }
        XCTAssertTrue(folderCell.waitForExistence(timeout: 8), "Folder \(folderName) should still be visible in repo listing")
        folderCell.press(forDuration: 1.2)

        // If a stale rank from an earlier run makes the menu show "Unfavorite", go through a
        // real unfavorite first so the favorite step below always exercises the full
        // fileproviderd -> extension setFavoriteRank path.
        let unfavoriteButton = filesApp.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Unfavorite' OR label CONTAINS '取消收藏'")
        ).firstMatch
        if unfavoriteButton.waitForExistence(timeout: 3) {
            unfavoriteButton.tap()
            sleep(2)
            folderCell = filesApp.cells.containing(.staticText, identifier: folderName).firstMatch
            XCTAssertTrue(folderCell.waitForExistence(timeout: 8), "Folder should still be listed after unfavorite")
            folderCell.press(forDuration: 1.2)
        }

        let favoriteButton = filesApp.buttons.matching(
            NSPredicate(format: "(label CONTAINS[c] 'Favorite' OR label CONTAINS '收藏') AND NOT (label CONTAINS[c] 'Unfavorite' OR label CONTAINS '取消收藏')")
        ).firstMatch
        if !favoriteButton.waitForExistence(timeout: 5) {
            let menuItem = filesApp.menuItems.matching(
                NSPredicate(format: "label CONTAINS[c] 'Favorite' OR label CONTAINS '收藏'")
            ).firstMatch
            XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "Favorite action should appear in context menu")
            menuItem.tap()
        } else {
            favoriteButton.tap()
        }

        sleep(2)

        XCTAssertEqual(countFavoriteEntries(named: folderName), 1,
                       "Should have exactly one favorite entry for \(folderName)")

        XCTAssertTrue(openFavoriteAndVerifyContents(named: folderName),
                      "Favorite sidebar entry should open with folder contents")

        XCTAssertTrue(verifyFolderContentsViaProvider(),
                      "Folder should still list server contents via provider after favoriting")

        // Simulate the user swiping the Files app away from the app switcher.
        filesApp.terminate()
        sleep(1)

        filesApp.launch()
        _ = filesApp.tabBars.buttons["Browse"].waitForExistence(timeout: 10)
        sleep(3)

        XCTAssertEqual(countFavoriteEntries(named: folderName), 1,
                       "Favorite should persist after Files app relaunch")

        XCTAssertTrue(openFavoriteAndVerifyContents(named: folderName),
                      "Favorite sidebar entry should still open with folder contents after relaunch")

        XCTAssertTrue(verifyFolderContentsViaProvider(),
                      "Folder should still list server contents via provider after relaunch")

        // A second cold start should still keep the same single favorite.
        filesApp.terminate()
        sleep(1)
        filesApp.launch()
        _ = filesApp.tabBars.buttons["Browse"].waitForExistence(timeout: 10)
        sleep(3)
        XCTAssertEqual(countFavoriteEntries(named: folderName), 1,
                       "Favorite should still be present after a second relaunch")

        XCTAssertTrue(verifyFolderContentsViaProvider(),
                      "Folder should still list server contents via provider after a second relaunch")
    }

    /// Diagnostic for the poisoned-daemon upgrade state: disabling and re-enabling the
    /// provider in the Files app Browse editor is the only user-reachable way (short of a
    /// reboot) to make fileproviderd re-register the domain. If a favorite made right after
    /// the toggle survives a relaunch, the toggle is a valid recovery step after upgrading
    /// from a build that answered the working-set enumerator with nil.
    func testIssue547_ToggleProviderThenFavoritePersists() throws {
        toggleSeafileProviderOffOn()

        navigateToFolderInSeafileProvider()
        removeFavoriteIfPresent(named: folderName)
        navigateToFolderInSeafileProvider()

        var folderCell = filesApp.cells.containing(.staticText, identifier: folderName).firstMatch
        if !folderCell.waitForExistence(timeout: 8) {
            folderCell = filesApp.staticTexts[folderName].firstMatch
        }
        XCTAssertTrue(folderCell.waitForExistence(timeout: 10), "Folder \(folderName) should be visible in Files app")
        folderCell.press(forDuration: 1.2)

        let unfavoriteButton = filesApp.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Unfavorite' OR label CONTAINS '取消收藏'")
        ).firstMatch
        if unfavoriteButton.waitForExistence(timeout: 3) {
            unfavoriteButton.tap()
            sleep(2)
            folderCell = filesApp.cells.containing(.staticText, identifier: folderName).firstMatch
            XCTAssertTrue(folderCell.waitForExistence(timeout: 8), "Folder should still be listed after unfavorite")
            folderCell.press(forDuration: 1.2)
        }

        let favoriteButton = filesApp.buttons.matching(
            NSPredicate(format: "(label CONTAINS[c] 'Favorite' OR label CONTAINS '收藏') AND NOT (label CONTAINS[c] 'Unfavorite' OR label CONTAINS '取消收藏')")
        ).firstMatch
        if !favoriteButton.waitForExistence(timeout: 5) {
            let menuItem = filesApp.menuItems.matching(
                NSPredicate(format: "label CONTAINS[c] 'Favorite' OR label CONTAINS '收藏'")
            ).firstMatch
            XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "Favorite action should appear in context menu")
            menuItem.tap()
        } else {
            favoriteButton.tap()
        }
        sleep(2)

        XCTAssertEqual(countFavoriteEntries(named: folderName), 1,
                       "Should have exactly one favorite entry for \(folderName) after toggle+favorite")

        filesApp.terminate()
        sleep(1)
        filesApp.launch()
        _ = filesApp.tabBars.buttons["Browse"].waitForExistence(timeout: 10)
        sleep(3)

        XCTAssertEqual(countFavoriteEntries(named: folderName), 1,
                       "Favorite should persist after Files app relaunch when provider was toggled first")
    }

    /// Browse root -> More (circled ellipsis) -> Edit Sidebar -> flip the SeafilePro switch
    /// off and back on -> Done. Screenshots at each step so a UI mismatch is diagnosable.
    private func toggleSeafileProviderOffOn() {
        let browse = filesApp.tabBars.buttons["Browse"]
        if browse.waitForExistence(timeout: 5) {
            browse.tap()
            sleep(1)
            browse.tap()
            sleep(1)
        }

        var moreButton = filesApp.navigationBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'More' OR identifier CONTAINS[c] 'More'")
        ).firstMatch
        if !moreButton.waitForExistence(timeout: 5) {
            moreButton = filesApp.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'More' OR identifier CONTAINS[c] 'More'")
            ).firstMatch
        }
        XCTAssertTrue(moreButton.waitForExistence(timeout: 8), "Browse root should offer the More button")
        moreButton.tap()
        sleep(1)
        attachShot("toggle-1-more-menu")

        let editEntry = filesApp.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Edit' OR label CONTAINS '编辑'")
        ).firstMatch
        let editMenuItem = filesApp.menuItems.matching(
            NSPredicate(format: "label CONTAINS[c] 'Edit' OR label CONTAINS '编辑'")
        ).firstMatch
        if editEntry.waitForExistence(timeout: 4) {
            editEntry.tap()
        } else {
            XCTAssertTrue(editMenuItem.waitForExistence(timeout: 4), "More menu should contain Edit")
            editMenuItem.tap()
        }
        sleep(1)
        attachShot("toggle-2-edit-mode")

        // The row switches carry no accessibility label (value only), so locate the switch
        // through the sidebar cell that carries the DOC.sidebar.item.SeafilePro identifier.
        var seafileSwitch = filesApp.cells["DOC.sidebar.item.SeafilePro"].switches.firstMatch
        if !seafileSwitch.waitForExistence(timeout: 6) {
            seafileSwitch = filesApp.cells.matching(
                NSPredicate(format: "label CONTAINS[c] 'Seafile'")
            ).firstMatch.switches.firstMatch
        }
        XCTAssertTrue(seafileSwitch.waitForExistence(timeout: 8), "Edit mode should show a switch for SeafilePro")

        seafileSwitch.tap()
        sleep(2)
        attachShot("toggle-3-after-off")
        seafileSwitch.tap()
        sleep(2)
        attachShot("toggle-4-after-on")

        let doneButton = filesApp.buttons.matching(
            NSPredicate(format: "label == 'Done' OR label == '完成'")
        ).firstMatch
        if doneButton.waitForExistence(timeout: 4) {
            doneButton.tap()
        }
        sleep(2)
        attachShot("toggle-5-done")
    }

    private func attachShot(_ name: String) {
        let shot = XCTAttachment(screenshot: filesApp.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func verifyFolderContentsViaProvider() -> Bool {
        navigateToFolderInSeafileProvider()
        var folderCell = filesApp.cells.containing(.staticText, identifier: folderName).firstMatch
        if !folderCell.waitForExistence(timeout: 8) {
            folderCell = filesApp.staticTexts[folderName].firstMatch
        }
        guard folderCell.waitForExistence(timeout: 10) else {
            return false
        }
        folderCell.tap()
        return waitForFolderContents()
    }

    private func navigateToFolderInSeafileProvider() {
        let browse = filesApp.tabBars.buttons["Browse"]
        if browse.waitForExistence(timeout: 3) {
            browse.tap()
        }

        var seafileLocation = filesApp.cells["DOC.sidebar.item.SeafilePro"]
        if !seafileLocation.waitForExistence(timeout: 12) {
            seafileLocation = filesApp.cells.matching(
                NSPredicate(format: "label CONTAINS[c] 'Seafile'")
            ).firstMatch
        }
        if !seafileLocation.waitForExistence(timeout: 12) {
            // Files may need a moment to register the provider after Seafile launches.
            sleep(3)
            if browse.waitForExistence(timeout: 2) {
                browse.tap()
            }
            seafileLocation = filesApp.cells.matching(
                NSPredicate(format: "label CONTAINS[c] 'Seafile'")
            ).firstMatch
        }
        if !seafileLocation.waitForExistence(timeout: 8) {
            // A leftover context menu or restored deep navigation can hide the Browse root;
            // a clean relaunch recovers it.
            filesApp.terminate()
            sleep(1)
            filesApp.launch()
            sleep(3)
            if browse.waitForExistence(timeout: 5) {
                browse.tap()
                sleep(1)
                browse.tap()
            }
            seafileLocation = filesApp.cells.matching(
                NSPredicate(format: "label CONTAINS[c] 'Seafile'")
            ).firstMatch
        }
        XCTAssertTrue(seafileLocation.waitForExistence(timeout: 12), "SeafilePro location should appear in Browse")
        seafileLocation.tap()

        let turnOnAlert = filesApp.alerts["Turn On “SeafilePro”?"]
        if turnOnAlert.waitForExistence(timeout: 3) {
            filesApp.buttons["Turn On"].tap()
        }

        // After enabling the provider, open it from the sidebar again.
        if browse.waitForExistence(timeout: 2) {
            browse.tap()
        }
        if seafileLocation.waitForExistence(timeout: 5) {
            seafileLocation.tap()
        }

        let accountCell = filesApp.cells.matching(
            NSPredicate(format: "label CONTAINS 'dev.seafile.com' OR label CONTAINS '5759610' OR label CONTAINS 'hhh'")
        ).firstMatch
        XCTAssertTrue(accountCell.waitForExistence(timeout: 15), "Seafile account should appear in Files app")
        accountCell.tap()

        var repoCell = filesApp.cells.containing(.staticText, identifier: repoName).firstMatch
        if !repoCell.waitForExistence(timeout: 15) {
            repoCell = filesApp.staticTexts[repoName].firstMatch
        }
        XCTAssertTrue(repoCell.waitForExistence(timeout: 20), "Repo \(repoName) should appear in Files app")
        repoCell.tap()
    }

    private func waitForFolderContents(timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if visibleItemCount() > 0 {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return false
    }

    private func visibleItemCount() -> Int {
        let grid = filesApp.collectionViews.element(boundBy: 0)
        if grid.exists && grid.cells.count > 0 {
            return grid.cells.count
        }
        let table = filesApp.tables.element(boundBy: 0)
        if table.exists && table.cells.count > 0 {
            return table.cells.count
        }
        return filesApp.cells.matching(
            NSPredicate(format: "NOT (identifier BEGINSWITH 'DOC.sidebar.')")
        ).count
    }

    /// Counts only DOC.sidebar.item cells: a repo listing that happens to contain a cell with
    /// the same name must not be mistaken for a sidebar favorite.
    private func countFavoriteEntries(named name: String) -> Int {
        goToBrowseRootAndExpandFavorites()
        for _ in 0..<4 {
            let sidebarMatches = filesApp.cells.matching(
                NSPredicate(format: "identifier BEGINSWITH 'DOC.sidebar.item.' AND label == %@", name)
            ).count
            if sidebarMatches > 0 {
                return sidebarMatches
            }
            sleep(1)
        }
        return 0
    }

    private func goToBrowseRootAndExpandFavorites() {
        let browse = filesApp.tabBars.buttons["Browse"]
        if browse.waitForExistence(timeout: 5) {
            browse.tap()
            sleep(1)
            // A second tap pops back to the Browse root when a location was open.
            browse.tap()
            sleep(1)
        }
        // The header tap TOGGLES the section, so only tap when no favorite rows are
        // visible (the device always has local folder favorites, so an expanded
        // section is never empty).
        let anyFavoriteRow = filesApp.cells.matching(
            NSPredicate(format: "identifier BEGINSWITH 'DOC.sidebar.item.'")
        )
        if anyFavoriteRow.count == 0 {
            let favoritesHeader = filesApp.cells["DOC.sidebar.header.Favorites"]
            if favoritesHeader.waitForExistence(timeout: 5) {
                favoritesHeader.tap()
                sleep(1)
            }
        }
    }

    private func removeFavoriteIfPresent(named name: String) {
        guard countFavoriteEntries(named: name) > 0 else { return }

        let sidebarCell = filesApp.cells.matching(
            NSPredicate(format: "identifier BEGINSWITH 'DOC.sidebar.item.' AND label == %@", name)
        ).firstMatch
        guard sidebarCell.waitForExistence(timeout: 5) else { return }
        sidebarCell.press(forDuration: 1.2)

        let unfavoriteButton = filesApp.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Unfavorite' OR label CONTAINS '取消收藏'")
        ).firstMatch
        if unfavoriteButton.waitForExistence(timeout: 5) {
            unfavoriteButton.tap()
            sleep(1)
        }
    }

    @discardableResult
    private func openFavoriteAndVerifyContents(named name: String) -> Bool {
        goToBrowseRootAndExpandFavorites()

        let favoriteCell = filesApp.cells.matching(
            NSPredicate(format: "identifier BEGINSWITH 'DOC.sidebar.item.' AND label == %@", name)
        ).firstMatch
        guard favoriteCell.waitForExistence(timeout: 8) else {
            return false
        }
        favoriteCell.tap()
        if !waitForFolderContents(timeout: 10) {
            favoriteCell.tap()
        }
        return waitForFolderContents(timeout: 25)
    }
}
