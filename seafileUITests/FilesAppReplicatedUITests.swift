import XCTest

/// Drives the system Files app against the replicated Seafile File Provider.
/// Needs a device where Seafile is installed and signed in; runs against the
/// first Seafile location it finds in the Browse sidebar.
final class FilesAppReplicatedUITests: XCTestCase {

    private let filesBundleID = "com.apple.DocumentsApp"
    private let seafileBundleID = "com.seafile.seafilePro"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Tests

    /// M1 + M2: the account location lists libraries, a library lists its
    /// content, and a file can be opened.
    func testLocationListsLibrariesAndOpensFile() throws {
        let files = launchFiles()
        try openSeafileLocation(in: files)
        waitForFilesContent(in: files, timeout: 30)
        let rootLabels = dumpVisibleLabels(in: files, label: "location-root")
        XCTAssertTrue(files.cells.count > 0, "Library list should not be empty")
        XCTAssertTrue(errorLabels(rootLabels).isEmpty, "No error state expected at the location root: \(errorLabels(rootLabels))")

        XCTAssertTrue(tapFirstCell(in: files), "Should be able to open the first library")
        waitForFilesContent(in: files, timeout: 30)
        let repoLabels = dumpVisibleLabels(in: files, label: "library-root")
        XCTAssertTrue(errorLabels(repoLabels).isEmpty, "No error state expected inside a library: \(errorLabels(repoLabels))")

        if tapFirstFileLikeCell(in: files) {
            Thread.sleep(forTimeInterval: 8)
            let previewLabels = dumpVisibleLabels(in: files, label: "file-preview")
            XCTAssertTrue(errorLabels(previewLabels).isEmpty, "Opening a file should not show an error: \(errorLabels(previewLabels))")
            closePreview(in: files)
        } else {
            print("=== NO_FILE_IN_LIBRARY_ROOT ===")
        }
    }

    /// Prints the Browse sidebar so the location names can be checked.
    func testDumpBrowseSidebar() throws {
        let files = launchFiles()
        reachBrowseRoot(in: files)
        dumpVisibleLabels(in: files, label: "browse-root")
    }

    // MARK: - Favorites (design §11.4)
    //
    // These need fixed test data on the signed-in account: a library named
    // `testLibrary` containing a folder named `testFolder`. Override with the
    // SEAF_TEST_LIBRARY / SEAF_TEST_FOLDER environment variables of the test
    // scheme. Not run in CI.

    private var testLibrary: String {
        ProcessInfo.processInfo.environment["SEAF_TEST_LIBRARY"] ?? "8888"
    }

    private var testFolder: String {
        ProcessInfo.processInfo.environment["SEAF_TEST_FOLDER"] ?? "Camera Uploads"
    }

    /// M3: favorite a folder, kill Files, reopen: the sidebar shows exactly one
    /// entry for it and the entry opens.
    func testFavoritePersistsAcrossFilesRestart() throws {
        var files = launchFiles()
        try openTestFolderParent(in: files)
        try setFavorite(true, folder: testFolder, in: files)
        defer { cleanupFavorite(folder: testFolder) }

        files = launchFiles()
        reachBrowseRoot(in: files)
        let entries = sidebarFavoriteEntries(named: testFolder, in: files)
        XCTAssertEqual(entries.count, 1, "Sidebar should list the favorite exactly once, got \(entries.count)")
        guard let entry = entries.first else { return }
        tapElement(entry)
        waitForFilesContent(in: files, timeout: 30)
        let labels = dumpVisibleLabels(in: files, label: "favorite-opened")
        XCTAssertTrue(errorLabels(labels).isEmpty, "Opening the favorite should not show an error: \(errorLabels(labels))")
    }

    /// M5: removing the favorite takes the sidebar entry away at once and it
    /// does not come back after Files is relaunched.
    func testUnfavoriteRemovesSidebarEntry() throws {
        var files = launchFiles()
        try openTestFolderParent(in: files)
        try setFavorite(true, folder: testFolder, in: files)
        reachBrowseRoot(in: files)
        XCTAssertEqual(sidebarFavoriteEntries(named: testFolder, in: files).count, 1, "Precondition: favorite listed once")

        try openTestFolderParent(in: files)
        try setFavorite(false, folder: testFolder, in: files)
        reachBrowseRoot(in: files)
        XCTAssertEqual(sidebarFavoriteEntries(named: testFolder, in: files).count, 0, "Sidebar entry should disappear immediately")

        files = launchFiles()
        reachBrowseRoot(in: files)
        XCTAssertEqual(sidebarFavoriteEntries(named: testFolder, in: files).count, 0, "Sidebar entry must not come back after relaunch")
    }

    /// M9: renaming a favorite folder keeps the favorite, now under the new name.
    func testRenameKeepsFavorite() throws {
        let renamed = testFolder + " renamed"
        let files = launchFiles()
        try openTestFolderParent(in: files)
        try setFavorite(true, folder: testFolder, in: files)
        defer {
            // Best effort: put the name back and drop the favorite.
            let cleanup = launchFiles()
            if (try? openTestFolderParent(in: cleanup)) != nil {
                if folderCell(named: renamed, in: cleanup).exists {
                    try? rename(folder: renamed, to: testFolder, in: cleanup)
                }
                try? setFavorite(false, folder: testFolder, in: cleanup)
            }
        }

        try rename(folder: testFolder, to: renamed, in: files)
        reachBrowseRoot(in: files)
        XCTAssertEqual(sidebarFavoriteEntries(named: renamed, in: files).count, 1, "Favorite should follow the rename")
        XCTAssertEqual(sidebarFavoriteEntries(named: testFolder, in: files).count, 0, "Old name must not linger in the sidebar")
    }

    // MARK: - Files helpers

    private func launchFiles() -> XCUIApplication {
        let files = XCUIApplication(bundleIdentifier: filesBundleID)
        files.terminate()
        files.activate()
        XCTAssertTrue(files.wait(for: .runningForeground, timeout: 30))
        Thread.sleep(forTimeInterval: 3)
        dismissFilesAlerts(in: files)
        return files
    }

    private func isSeafileLocationLabel(_ label: String) -> Bool {
        let name = label.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? label
        if name.localizedCaseInsensitiveContains("iCloud") { return false }
        // Replicated domains are named "<display name> – <host>" (login as fallback).
        return name.contains(" – ") || name.localizedCaseInsensitiveContains("Seafile")
    }

    private func seafileLocationCandidates(in files: XCUIApplication) -> [XCUIElement] {
        var matches: [XCUIElement] = []
        for query in [files.cells, files.staticTexts, files.buttons] {
            for element in query.allElementsBoundByIndex.prefix(80) {
                let text = element.label.isEmpty ? element.identifier : element.label
                if isSeafileLocationLabel(text) {
                    matches.append(element)
                }
            }
        }
        return matches
    }

    private func openSeafileLocation(in files: XCUIApplication) throws {
        reachBrowseRoot(in: files)
        dumpVisibleLabels(in: files, label: "browse-before-open")
        for step in 0..<10 {
            for match in seafileLocationCandidates(in: files) {
                let title = match.label.isEmpty ? match.identifier : match.label
                if match.isHittable {
                    print("=== OPEN_SEAFILE_LOCATION label=\(title) ===")
                    match.tap()
                    Thread.sleep(forTimeInterval: 3)
                    tapRetryIfContentUnavailable(in: files)
                    return
                }
            }
            if step % 2 == 0 { files.swipeDown() } else { files.swipeUp() }
            Thread.sleep(forTimeInterval: 1)
        }
        dumpVisibleLabels(in: files, label: "seafile-location-missing")
        XCTFail("Seafile location not found in Files browse sidebar")
    }

    private func waitForFilesContent(in files: XCUIApplication, timeout: TimeInterval) {
        tapRetryIfContentUnavailable(in: files)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let loading = files.staticTexts["正在载入"].firstMatch
            let loadingEn = files.staticTexts["Loading"].firstMatch
            if loading.exists || loadingEn.exists {
                Thread.sleep(forTimeInterval: 1.2)
                tapRetryIfContentUnavailable(in: files)
                continue
            }
            break
        }
        Thread.sleep(forTimeInterval: 2)
    }

    private func tapRetryIfContentUnavailable(in files: XCUIApplication) {
        for label in ["重试", "Retry"] {
            let retry = files.buttons[label].firstMatch
            if retry.waitForExistence(timeout: 1) && retry.isHittable {
                print("=== TAP_RETRY ===")
                retry.tap()
                Thread.sleep(forTimeInterval: 4)
            }
        }
    }

    private func tapFirstCell(in files: XCUIApplication) -> Bool {
        let cell = files.cells.firstMatch
        guard cell.waitForExistence(timeout: 10) else { return false }
        print("=== TAP_CELL \(cell.label) ===")
        tapElement(cell)
        Thread.sleep(forTimeInterval: 3)
        return true
    }

    private func tapFirstFileLikeCell(in files: XCUIApplication) -> Bool {
        let cells = files.cells.allElementsBoundByIndex.prefix(40)
        for cell in cells {
            let name = cell.label.components(separatedBy: ",").first ?? cell.label
            let ext = (name as NSString).pathExtension.lowercased()
            if !ext.isEmpty && ext.count <= 5 && cell.isHittable {
                print("=== TAP_FILE \(name) ===")
                tapElement(cell)
                return true
            }
        }
        return false
    }

    private func closePreview(in files: XCUIApplication) {
        for label in ["完成", "Done"] {
            let done = files.buttons[label].firstMatch
            if done.exists && done.isHittable {
                done.tap()
                Thread.sleep(forTimeInterval: 1)
                return
            }
        }
        let back = files.navigationBars.buttons.firstMatch
        if back.exists && back.isHittable {
            back.tap()
        }
    }

    private func tapElement(_ item: XCUIElement) {
        if item.isHittable {
            item.tap()
            return
        }
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func errorLabels(_ labels: [String]) -> [String] {
        let markers = ["内容不可用", "Content Unavailable", "已暂停", "paused", "无法", "错误", "Error", "重试", "Retry", "无法载入", "Couldn’t"]
        return labels.filter { label in markers.contains { label.localizedCaseInsensitiveContains($0) } }
    }

    @discardableResult
    private func dumpVisibleLabels(in files: XCUIApplication, label: String) -> [String] {
        var seen: [String] = []
        for query in [files.navigationBars, files.cells, files.staticTexts, files.buttons] {
            for element in query.allElementsBoundByIndex.prefix(60) {
                let text = element.label.isEmpty ? element.identifier : element.label
                if !text.isEmpty && !seen.contains(text) {
                    seen.append(text)
                }
            }
        }
        print("=== LABELS[\(label)] \(seen) ===")
        return seen
    }

    private func dismissFilesAlerts(in files: XCUIApplication) {
        for _ in 0..<3 {
            let alert = files.alerts.firstMatch
            if !alert.waitForExistence(timeout: 1) { return }
            print("=== FILES_ALERT \(alert.label) ===")
            for label in ["允许", "Allow", "好", "OK", "关闭", "Close"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    Thread.sleep(forTimeInterval: 0.5)
                    break
                }
            }
        }
    }

    // MARK: - Favorites helpers

    /// Opens the Seafile location, then the test library, so `testFolder` is on screen.
    private func openTestFolderParent(in files: XCUIApplication) throws {
        try openSeafileLocation(in: files)
        waitForFilesContent(in: files, timeout: 30)
        let library = folderCell(named: testLibrary, in: files)
        guard library.waitForExistence(timeout: 15) else {
            dumpVisibleLabels(in: files, label: "library-missing")
            throw XCTSkip("Library \(testLibrary) not found in the Seafile location")
        }
        tapElement(library)
        waitForFilesContent(in: files, timeout: 30)
        let folder = folderCell(named: testFolder, in: files)
        guard folder.waitForExistence(timeout: 15) else {
            dumpVisibleLabels(in: files, label: "folder-missing")
            throw XCTSkip("Folder \(testFolder) not found in library \(testLibrary)")
        }
    }

    private func folderCell(named name: String, in files: XCUIApplication) -> XCUIElement {
        // Cell labels read "<name>, <details>" in the list layout.
        let predicate = NSPredicate(format: "label BEGINSWITH %@ OR label == %@", name + ",", name)
        return files.cells.matching(predicate).firstMatch
    }

    /// Long-presses a folder and picks the (un)favorite entry of the context menu.
    private func setFavorite(_ favorite: Bool, folder: String, in files: XCUIApplication) throws {
        let cell = folderCell(named: folder, in: files)
        guard cell.waitForExistence(timeout: 10) else { throw XCTSkip("Folder \(folder) not on screen") }
        cell.press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1)
        let wanted = favorite
            ? ["个人收藏", "添加到个人收藏", "Favorite", "Add to Favorites"]
            : ["取消个人收藏", "从个人收藏中移除", "Unfavorite", "Remove from Favorites"]
        let unwanted = favorite
            ? ["取消个人收藏", "从个人收藏中移除", "Unfavorite", "Remove from Favorites"]
            : ["个人收藏", "添加到个人收藏", "Favorite", "Add to Favorites"]
        if tapContextMenuButton(labels: wanted, in: files) {
            Thread.sleep(forTimeInterval: 2)
            return
        }
        if tapContextMenuButton(labels: unwanted, in: files, dryRun: true) {
            // Already in the wanted state.
            dismissContextMenu(in: files)
            return
        }
        dumpVisibleLabels(in: files, label: "context-menu")
        dismissContextMenu(in: files)
        XCTFail("Context menu has no favorite entry for \(folder)")
    }

    private func rename(folder: String, to newName: String, in files: XCUIApplication) throws {
        let cell = folderCell(named: folder, in: files)
        guard cell.waitForExistence(timeout: 10) else { throw XCTSkip("Folder \(folder) not on screen") }
        cell.press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1)
        guard tapContextMenuButton(labels: ["重新命名", "重命名", "Rename"], in: files) else {
            dismissContextMenu(in: files)
            XCTFail("Context menu has no rename entry for \(folder)")
            return
        }
        Thread.sleep(forTimeInterval: 1)
        let field = files.textFields.firstMatch
        guard field.waitForExistence(timeout: 5) else {
            XCTFail("Rename field did not appear")
            return
        }
        replaceText(in: field, with: newName, app: files)
        files.keyboards.buttons["完成"].exists ? files.keyboards.buttons["完成"].tap() : files.typeText("\n")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(folderCell(named: newName, in: files).waitForExistence(timeout: 15), "Renamed folder should be listed")
    }

    /// Closes an open context menu by tapping the status-bar strip, which is
    /// never covered by the menu (the app's centre point may be a menu row).
    private func dismissContextMenu(in files: XCUIApplication) {
        files.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap()
        Thread.sleep(forTimeInterval: 1)
    }

    /// Replaces the field's text: select-all when the edit menu offers it,
    /// otherwise delete from the end character by character.
    private func replaceText(in field: XCUIElement, with text: String, app files: XCUIApplication) {
        field.tap()
        field.press(forDuration: 1.0)
        if tapContextMenuButton(labels: ["全选", "Select All"], in: files) {
            Thread.sleep(forTimeInterval: 0.3)
        } else {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            let existing = (field.value as? String) ?? ""
            if !existing.isEmpty {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 2))
            }
        }
        field.typeText(text)
    }

    /// Taps the first context-menu button whose label matches; with dryRun only reports presence.
    private func tapContextMenuButton(labels: [String], in files: XCUIApplication, dryRun: Bool = false) -> Bool {
        for label in labels {
            let button = files.buttons[label].firstMatch
            if button.waitForExistence(timeout: 1) {
                if !dryRun { button.tap() }
                return true
            }
            let text = files.staticTexts[label].firstMatch
            if text.exists {
                if !dryRun { text.tap() }
                return true
            }
        }
        return false
    }

    /// Sidebar rows of the Browse root that show the favorite by name. The
    /// Favorites section lists one cell per favorite; a duplicate here is the
    /// bug of issue 547.
    private func sidebarFavoriteEntries(named name: String, in files: XCUIApplication) -> [XCUIElement] {
        let predicate = NSPredicate(format: "label == %@ OR label BEGINSWITH %@ OR identifier == %@",
                                    name, name + ",", "DOC.sidebar.item." + name)
        return files.cells.matching(predicate).allElementsBoundByIndex
    }

    private func cleanupFavorite(folder: String) {
        let files = launchFiles()
        guard (try? openTestFolderParent(in: files)) != nil else { return }
        try? setFavorite(false, folder: folder, in: files)
    }

    private func reachBrowseRoot(in files: XCUIApplication) {
        for label in ["浏览", "Browse"] {
            let tab = files.buttons[label]
            if tab.exists && tab.isHittable {
                tab.tap()
                Thread.sleep(forTimeInterval: 2)
                break
            }
        }
        for _ in 0..<4 {
            let back = files.navigationBars.buttons.firstMatch
            if back.exists && back.isHittable && (back.label == "浏览" || back.label == "Browse" || back.label.isEmpty) {
                back.tap()
                Thread.sleep(forTimeInterval: 1)
            } else {
                break
            }
        }
        Thread.sleep(forTimeInterval: 1)
    }
}
