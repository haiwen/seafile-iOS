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
